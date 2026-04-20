// kulms-textbook-handler.js — Textbook search handler for WebView
// Ported from extension's background.js for use in iOS/Android WebView.
// Cross-origin requests (KULASIS syllabus) use window.__kulmsNativeFetch()
// (native HTTP proxy, CORS-free, charset auto-detected).
// Same-origin requests (Sakai API) use regular fetch().

(function () {
  "use strict";

  if (!window.__kulmsMessageHandlers) {
    window.__kulmsMessageHandlers = {};
  }

  var SYLLABUS_BASE = "https://www.k.kyoto-u.ac.jp/external/open_syllabus";
  var LMS_BASE = "https://lms.gakusei.kyoto-u.ac.jp";

  function cleanCourseName(name) {
    return name
      .replace(/^\s*\[[^\]]*\]\s*/, "")
      .replace(/\s*\(.*\)\s*$/, "")
      .trim();
  }

  function normalizeForMatch(str) {
    return str
      .replace(/[\uFF01-\uFF5E]/g, function (ch) {
        return String.fromCharCode(ch.charCodeAt(0) - 0xfee0);
      })
      .replace(/\u3000/g, " ")
      .replace(/\s+/g, " ")
      .trim();
  }

  function normalizeTeacherName(str) {
    return String(str || "")
      .replace(/[\s\u3000\u00A0]+/g, "")
      .trim();
  }

  var sjisEncodeTable = null;

  function buildSjisEncodeTable() {
    var map = new Map();
    var decoder = new TextDecoder("shift_jis", { fatal: true });

    for (var hi = 0x81; hi <= 0xfc; hi++) {
      if (hi >= 0xa0 && hi <= 0xdf) continue;
      for (var lo = 0x40; lo <= 0xfc; lo++) {
        if (lo === 0x7f) continue;
        try {
          var bytes = new Uint8Array([hi, lo]);
          var ch = decoder.decode(bytes);
          if (ch.length === 1 && !map.has(ch)) {
            map.set(ch, [hi, lo]);
          }
        } catch (e) {}
      }
    }

    for (var b = 0xa1; b <= 0xdf; b++) {
      try {
        var bytes = new Uint8Array([b]);
        var ch = decoder.decode(bytes);
        if (ch.length === 1 && !map.has(ch)) {
          map.set(ch, [b]);
        }
      } catch (e) {}
    }

    return map;
  }

  function encodeShiftJIS(str) {
    if (!sjisEncodeTable) sjisEncodeTable = buildSjisEncodeTable();
    var encoded = "";
    for (var char of str) {
      var code = char.charCodeAt(0);
      if (
        (code >= 0x30 && code <= 0x39) ||
        (code >= 0x41 && code <= 0x5a) ||
        (code >= 0x61 && code <= 0x7a) ||
        code === 0x2d || code === 0x2e || code === 0x5f || code === 0x7e
      ) {
        encoded += char;
        continue;
      }
      if (code === 0x20) {
        encoded += "+";
        continue;
      }
      var bytes = sjisEncodeTable.get(char);
      if (bytes) {
        for (var j = 0; j < bytes.length; j++) {
          encoded += "%" + bytes[j].toString(16).toUpperCase().padStart(2, "0");
        }
      } else if (code < 0x80) {
        encoded += "%" + code.toString(16).toUpperCase().padStart(2, "0");
      }
    }
    return encoded;
  }

  // Native fetch proxy for cross-origin KULASIS requests.
  // Native side handles charset detection & decoding; returns plain text.
  async function fetchAndDecode(url) {
    return await window.__kulmsNativeFetch(url);
  }

  // Sakai site contact (same-origin, uses regular fetch)
  async function fetchSakaiSiteContact(siteId) {
    if (!siteId) return null;
    try {
      var pagesRes = await fetch(
        LMS_BASE + "/direct/site/" + encodeURIComponent(siteId) + "/pages.json",
        { credentials: "include" }
      );
      if (!pagesRes.ok) return null;
      var pages = await pagesRes.json();
      var placementId = null;
      for (var i = 0; i < (pages || []).length; i++) {
        var p = pages[i];
        for (var j = 0; j < (p.tools || []).length; j++) {
          var t = p.tools[j];
          if (t.toolId === "sakai.siteinfo") {
            placementId = t.placementId;
            break;
          }
        }
        if (placementId) break;
      }
      if (!placementId) return null;

      var htmlRes = await fetch(
        LMS_BASE + "/portal/tool/" + encodeURIComponent(placementId),
        { credentials: "include" }
      );
      if (!htmlRes.ok) return null;
      var html = await htmlRes.text();

      var m = html.match(
        /サイト連絡先[・･\u30FB]?メール[\s\S]*?<td[^>]*>\s*([^,<\n]+?)\s*(?:,|<)/
      );
      if (!m) return null;
      var name = m[1].trim();
      if (!name || /<|>/.test(name)) return null;
      return name;
    } catch (e) {
      console.warn("[KULMS] fetchSakaiSiteContact error:", e.message);
      return null;
    }
  }

  async function searchSyllabus(keyword, options) {
    options = options || {};
    var searchUrl =
      SYLLABUS_BASE +
      "/search?condition.keyword=" +
      encodeShiftJIS(keyword) +
      "&condition.departmentNo=&condition.openSyllabusTitle=" +
      "&condition.courseNumberingJugyokeitaiNo=&condition.courseNumberingLanguageNo=" +
      "&condition.semesterNo=&condition.courseNumberingLevelNo=" +
      "&condition.courseNumberingBunkaNo=&condition.teacherName=" +
      "&x=0&y=0";

    console.log("[KULMS] searching syllabus for:", keyword);
    var html = await fetchAndDecode(searchUrl);

    var rowRe = /<tr[^>]*>([\s\S]*?)<\/tr>/gi;
    var results = [];
    var seen = new Set();
    var rm;
    while ((rm = rowRe.exec(html)) !== null) {
      var rowHtml = rm[1];
      var lectureMatch = rowHtml.match(
        /(?:department_syllabus|la_syllabus)\?lectureNo=(\d+)(?:&(?:amp;)?departmentNo=(\d+))?/
      );
      if (!lectureMatch) continue;
      var lectureNo = lectureMatch[1];
      var departmentNo = lectureMatch[2] || "";
      if (seen.has(lectureNo)) continue;
      seen.add(lectureNo);

      var tdRe = /<td[^>]*>([\s\S]*?)<\/td>/gi;
      var cells = [];
      var td;
      while ((td = tdRe.exec(rowHtml)) !== null) {
        var text = td[1].replace(/<[^>]+>/g, "").replace(/\s+/g, " ").trim();
        if (text && text.length > 1) cells.push(text);
      }

      var name = cells[0] || "";
      var teacherName = cells[1] || "";
      if (name) {
        results.push({ lectureNo: lectureNo, departmentNo: departmentNo, name: name, teacherName: teacherName });
      }
    }

    console.log("[KULMS] search results:", results.length, "entries");
    if (results.length === 0) return null;
    if (results.length <= 5) {
      console.log(
        "[KULMS] results:",
        results.map(function (r) { return r.name; }).join(", ")
      );
    }

    var matchTarget = options.expectedName || keyword;
    var normalized = normalizeForMatch(matchTarget);

    function pickResult(r, label) {
      console.log("[KULMS]", label + ":", r.name, "/", r.teacherName, r.lectureNo);
      return { lectureNo: r.lectureNo, departmentNo: r.departmentNo };
    }

    var exactMatches = results.filter(function (r) {
      return normalizeForMatch(r.name) === normalized;
    });
    if (exactMatches.length === 1) {
      return pickResult(exactMatches[0], "exact match");
    }
    if (exactMatches.length > 1) {
      var winner = await disambiguateByTeacher(exactMatches, options);
      if (winner) return pickResult(winner, "exact match (teacher-disambiguated)");
      return pickResult(exactMatches[0], "exact match (first of " + exactMatches.length + ", teacher unknown)");
    }

    var partialMatches = results.filter(function (r) {
      var rn = normalizeForMatch(r.name);
      return rn.includes(normalized) || normalized.includes(rn);
    });
    if (partialMatches.length === 1) {
      return pickResult(partialMatches[0], "partial match");
    }
    if (partialMatches.length > 1) {
      var winner = await disambiguateByTeacher(partialMatches, options);
      if (winner) return pickResult(winner, "partial match (teacher-disambiguated)");
      return pickResult(partialMatches[0], "partial match (first of " + partialMatches.length + ", teacher unknown)");
    }

    if (options.expectedName) {
      console.log(
        "[KULMS] no name match for expectedName:",
        options.expectedName,
        "(keyword:",
        keyword + ")"
      );
      return null;
    }

    console.log(
      "[KULMS] using first result:",
      results[0].name,
      results[0].lectureNo
    );
    return { lectureNo: results[0].lectureNo, departmentNo: results[0].departmentNo };
  }

  async function disambiguateByTeacher(candidates, options) {
    if (!options.expectedTeacher) return null;
    var teacher = options.expectedTeacher;
    if (typeof teacher === "function") {
      try {
        teacher = await teacher();
      } catch (e) {
        console.warn("[KULMS] expectedTeacher fetch failed:", e.message);
        teacher = null;
      }
    }
    if (!teacher) return null;
    var teacherKey = normalizeTeacherName(teacher);
    if (!teacherKey) return null;
    console.log("[KULMS] disambiguating by teacher:", teacher);
    var found = candidates.find(function (c) {
      var ck = normalizeTeacherName(c.teacherName || "");
      return ck && (ck.includes(teacherKey) || teacherKey.includes(ck));
    });
    return found || null;
  }

  async function fetchSyllabusDetail(lectureNo, departmentNo) {
    var url = departmentNo
      ? SYLLABUS_BASE + "/department_syllabus?lectureNo=" + lectureNo + "&departmentNo=" + departmentNo
      : SYLLABUS_BASE + "/la_syllabus?lectureNo=" + lectureNo;
    var html = await fetchAndDecode(url);
    var books = [];

    var text = html
      .replace(/<style[^>]*>[\s\S]*?<\/style>/gi, "")
      .replace(/<script[^>]*>[\s\S]*?<\/script>/gi, "")
      .replace(/<br\s*\/?>/gi, "\n")
      .replace(/<\/(?:div|p|tr|td|th|li|h[1-6])>/gi, "\n")
      .replace(/<[^>]+>/g, " ")
      .replace(/&nbsp;/g, " ")
      .replace(/&amp;/g, "&")
      .replace(/&lt;/g, "<")
      .replace(/&gt;/g, ">")
      .replace(/&#\d+;/g, "")
      .replace(/[ \t]+/g, " ");

    var sectionHeadings =
      /(?:教科書|参考書|テキスト|参考文献|予習|復習|成績|授業外|履修|その他|備考|関連URL|オフィスアワー)/;
    var textbookHeadings = /(?:教科書|テキスト)/;
    var referenceHeadings = /(?:参考書|参考文献)/;
    var targetHeadings = /(?:教科書|参考書|テキスト|参考文献)/;

    var lines = text.split("\n").map(function (l) { return l.trim(); });
    var currentType = null;

    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];

      if (line.length < 30 && targetHeadings.test(line)) {
        if (textbookHeadings.test(line)) {
          currentType = "textbook";
        } else if (referenceHeadings.test(line)) {
          currentType = "reference";
        }
        continue;
      }
      if (
        currentType &&
        line.length < 30 &&
        sectionHeadings.test(line) &&
        !targetHeadings.test(line)
      ) {
        currentType = null;
        continue;
      }

      if (!currentType) continue;
      if (line.length < 4) continue;
      if (/^(?:特になし|なし|使用しない|No textbook|None)/i.test(line)) {
        currentType = null;
        continue;
      }

      var author = "";
      var title = "";
      var publisher = "";
      var isbn = "";

      var isbnMatch = line.match(/ISBN[:\s{}-]*([\d][\d-]{7,16}[\d])/i);
      if (isbnMatch) {
        isbn = isbnMatch[1].replace(/-/g, "");
      }

      var bracketMatch = line.match(/^(.*?)\u300E(.+?)\u300F/);
      if (bracketMatch) {
        author = bracketMatch[1]
          .replace(/[,、]\s*$/, "")
          .trim();
        title = bracketMatch[2].trim();

        var pubMatch = line.match(/[\uFF08(]([^\uFF09)]+)[\uFF09)]/);
        if (pubMatch) {
          publisher = pubMatch[1]
            .replace(/[、,]\s*\d{4}\u5E74?/, "")
            .trim();
        }
      } else {
        title = line
          .replace(/ISBN[:\s{}-]*[\d-]+/gi, "")
          .replace(/\d{4}\u5E74?$/g, "")
          .replace(/[\s,\u3001;\uFF1B]+$/g, "")
          .trim();

        var pubFallback = line.match(
          /[,\u3001]\s*([^,\u3001]+?(?:\u793E|\u51FA\u7248|\u66F8[\u5E97\u9662\u623F]|\u30D7\u30EC\u30B9|Press|Publishing|University Press))/i
        );
        if (pubFallback) {
          publisher = pubFallback[1].trim();
          title = title.replace(publisher, "").replace(/[,\u3001]\s*$/, "").trim();
        }
      }

      if (title && title.length > 2) {
        books.push({ title: title, author: author, publisher: publisher, isbn: isbn, type: currentType });
      }
    }

    var seen = new Set();
    return books.filter(function (b) {
      var key = b.type + ":" + b.title.substring(0, 20);
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    });
  }

  // Register handler for chrome.runtime.sendMessage({ action: "fetchTextbooks" })
  window.__kulmsMessageHandlers["fetchTextbooks"] = async function (message) {
    var courseName = message.courseName;
    var siteId = String(message.siteId || "").trim();
    var lectureCode = String(message.lectureCode || "").trim().toUpperCase();
    if (!courseName && !lectureCode) {
      return { books: [] };
    }

    var keyword = cleanCourseName(courseName || "");
    if (!lectureCode && !keyword) {
      return { books: [] };
    }

    var teacherPromise = null;
    var lazyTeacher = function () {
      if (!siteId) return Promise.resolve(null);
      if (!teacherPromise) teacherPromise = fetchSakaiSiteContact(siteId);
      return teacherPromise;
    };

    try {
      if (lectureCode && keyword) {
        var matched = await searchSyllabus(lectureCode, {
          expectedName: keyword,
          expectedTeacher: lazyTeacher
        });
        if (matched) {
          var syllabusUrl = matched.departmentNo
            ? SYLLABUS_BASE + "/department_syllabus?lectureNo=" + matched.lectureNo + "&departmentNo=" + matched.departmentNo
            : SYLLABUS_BASE + "/la_syllabus?lectureNo=" + matched.lectureNo;
          var books = await fetchSyllabusDetail(matched.lectureNo, matched.departmentNo);
          return { books: books, syllabusUrl: syllabusUrl };
        }
        console.log("[KULMS] lectureCode search did not match name, falling back to name search");
      }

      var result = await searchSyllabus(keyword, {
        expectedTeacher: lazyTeacher
      });
      if (!result) {
        return { books: [] };
      }
      var syllabusUrl = result.departmentNo
        ? SYLLABUS_BASE + "/department_syllabus?lectureNo=" + result.lectureNo + "&departmentNo=" + result.departmentNo
        : SYLLABUS_BASE + "/la_syllabus?lectureNo=" + result.lectureNo;
      var books = await fetchSyllabusDetail(result.lectureNo, result.departmentNo);
      return { books: books, syllabusUrl: syllabusUrl };
    } catch (e) {
      console.warn("[KULMS] textbook fetch error:", e.message);
      return { books: [], error: e.message };
    }
  };

  console.log("[kulms-textbook-handler] registered fetchTextbooks handler");
})();
