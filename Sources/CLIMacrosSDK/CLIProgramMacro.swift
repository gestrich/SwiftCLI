import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct CLIProgramMacro: ExtensionMacro, MemberMacro {

    // MARK: - ExtensionMacro

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            throw MacroError.message("@CLIProgramMacro can only be applied to structs")
        }

        let structName = structDecl.name.text

        // Extract explicit name from macro arguments if provided
        let programName = extractExplicitName(from: node) ?? toKebabCase(structName)

        // Check if this program has CLI properties (making it also a command)
        let properties = parseProperties(from: structDecl)
        let hasCLIProperties = properties.contains { prop in
            if case .none = prop.attribute { return false }
            return true
        }

        if hasCLIProperties {
            // Program is also a command (no subcommands, flags go directly on program)
            let argumentsCode = generateArgumentsCode(properties: properties)

            let extensionDecl = try ExtensionDeclSyntax("extension \(type): CLIProgram, CLICommand") {
                """
                public static var programName: String { \(literal: programName) }

                public typealias Program = \(raw: structName)

                public static var commandPath: [String] { [] }

                public var arguments: [CLIArgument] {
                    var args: [CLIArgument] = []
                    \(raw: argumentsCode)
                    return args
                }
                """
            }

            return [extensionDecl]
        } else {
            // Program with nested command structs
            let extensionDecl = try ExtensionDeclSyntax("extension \(type): CLIProgram") {
                """
                public static var programName: String { \(literal: programName) }
                """
            }

            return [extensionDecl]
        }
    }

    // MARK: - MemberMacro

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            throw MacroError.message("@CLIProgramMacro can only be applied to structs")
        }

        // Check if this program has CLI properties (making it also a command)
        let properties = parseProperties(from: structDecl)
        let hasCLIProperties = properties.contains { prop in
            if case .none = prop.attribute { return false }
            return true
        }

        // Only generate initializer if this is a program+command
        if hasCLIProperties {
            let initDecl = generateInitializer(properties: properties)
            return [DeclSyntax(initDecl)]
        }

        return []
    }

    // MARK: - Helpers

    private static func extractExplicitName(from node: AttributeSyntax) -> String? {
        guard let arguments = node.arguments?.as(LabeledExprListSyntax.self),
              let firstArg = arguments.first,
              let stringLiteral = firstArg.expression.as(StringLiteralExprSyntax.self),
              let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) else {
            return nil
        }
        return segment.content.text
    }
}

enum MacroError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case .message(let text):
            return text
        }
    }
}

/// Convert PascalCase/camelCase to kebab-case
func toKebabCase(_ string: String) -> String {
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
