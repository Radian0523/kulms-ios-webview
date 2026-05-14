import Foundation
import CommonCrypto

/// RFC 6238 TOTP コードを生成するユーティリティ。
/// 外部依存なし（CommonCrypto のみ使用）。
enum TOTPGenerator {
    /// Base32 シークレットから 6 桁の TOTP コードを生成する。
    static func generate(secret: String) -> String? {
        guard let key = base32Decode(secret) else { return nil }

        // 現在の UNIX 時間を 30 秒ステップに変換（RFC 6238 デフォルト）
        var counter = UInt64(Date().timeIntervalSince1970 / 30).bigEndian

        // HMAC-SHA1
        var hmac = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        withUnsafeBytes(of: &counter) { counterBytes in
            CCHmac(
                CCHmacAlgorithm(kCCHmacAlgSHA1),
                key, key.count,
                counterBytes.baseAddress!, counterBytes.count,
                &hmac
            )
        }

        // Dynamic Truncation (RFC 4226 Section 5.4)
        let offset = Int(hmac[19] & 0x0f)
        let code = (UInt32(hmac[offset]) & 0x7f) << 24
            | UInt32(hmac[offset + 1]) << 16
            | UInt32(hmac[offset + 2]) << 8
            | UInt32(hmac[offset + 3])
        let otp = code % 1_000_000

        return String(format: "%06d", otp)
    }

    /// Base32 バリデーション（保存前チェック用）。
    static func isValidBase32(_ input: String) -> Bool {
        let cleaned = input.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .uppercased()
        guard !cleaned.isEmpty else { return false }
        let base32Chars = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567=")
        return cleaned.unicodeScalars.allSatisfy { base32Chars.contains($0) }
    }

    // MARK: - Base32 Decode

    private static let base32Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"

    private static func base32Decode(_ input: String) -> [UInt8]? {
        let cleaned = input.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "=", with: "")
            .uppercased()
        guard !cleaned.isEmpty else { return nil }

        var output = [UInt8]()
        var buffer: UInt64 = 0
        var bitsLeft = 0

        for char in cleaned {
            guard let index = base32Alphabet.firstIndex(of: char) else { return nil }
            let value = UInt64(base32Alphabet.distance(from: base32Alphabet.startIndex, to: index))
            buffer = (buffer << 5) | value
            bitsLeft += 5

            if bitsLeft >= 8 {
                bitsLeft -= 8
                output.append(UInt8((buffer >> bitsLeft) & 0xff))
            }
        }

        return output
    }
}
