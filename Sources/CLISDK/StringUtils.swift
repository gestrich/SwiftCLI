/// Utility functions for string transformations
public enum StringUtils {
    /// Convert a camelCase or PascalCase string to kebab-case
    /// Examples:
    ///   - "noFastForward" -> "no-fast-forward"
    ///   - "UpdateIndex" -> "update-index"
    ///   - "force" -> "force"
    public static func toKebabCase(_ string: String) -> String {
        var result = ""
        for (index, char) in string.enumerated() {
            if char.isUppercase {
                if index > 0 {
                    result.append("-")
                }
                result.append(char.lowercased())
            } else {
                result.append(char)
            }
        }
        return result
    }
}
