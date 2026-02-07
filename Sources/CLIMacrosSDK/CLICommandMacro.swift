import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Information about a command in the hierarchy
private struct CommandInfo {
    let typeName: String
    let commandName: String
    let isProgram: Bool
}

public struct CLICommandMacro: ExtensionMacro, MemberMacro {

    // MARK: - ExtensionMacro

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            throw MacroError.message("@CLICommandMacro can only be applied to structs")
        }

        let structName = structDecl.name.text

        // Extract explicit name from macro arguments if provided
        let explicitName = extractExplicitName(from: node)

        // Extract full command chain from lexical context
        let chain = extractCommandChain(from: context)

        // Build commandPath from chain (skip the program, include all intermediate commands + this command)
        var commandPath: [String] = []
        for info in chain where !info.isProgram {
            // Skip empty command names in the chain
            if !info.commandName.isEmpty {
                commandPath.append(info.commandName)
            }
        }
        // Add current command name (empty string means no subcommand, like `ls` without any subcommand)
        let currentCommandName = explicitName ?? toKebabCase(structName)
        if !currentCommandName.isEmpty {
            commandPath.append(currentCommandName)
        }

        // Find root program type (first item in chain should be @CLIProgram)
        let programType = chain.first?.typeName ?? "_UnknownProgram"

        // Parse properties with CLI attributes
        let properties = parseProperties(from: structDecl)

        // Generate arguments computed property
        let argumentsCode = generateArgumentsCode(properties: properties)

        // Generate commandPath array literal
        let commandPathLiteral = commandPath.map { "\"\($0)\"" }.joined(separator: ", ")

        // If no arguments code, use a simpler implementation to avoid "var never mutated" warning
        let argumentsProperty: String
        if argumentsCode.isEmpty {
            argumentsProperty = "public var arguments: [CLIArgument] { [] }"
        } else {
            argumentsProperty = """
            public var arguments: [CLIArgument] {
                    var args: [CLIArgument] = []
                    \(argumentsCode)
                    return args
                }
            """
        }

        let extensionDecl = try ExtensionDeclSyntax("extension \(type): CLICommand") {
            """
            public typealias Program = \(raw: programType)

            public static var commandPath: [String] { [\(raw: commandPathLiteral)] }

            \(raw: argumentsProperty)
            """
        }

        return [extensionDecl]
    }

    // MARK: - MemberMacro

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            throw MacroError.message("@CLICommandMacro can only be applied to structs")
        }

        // Parse properties to generate memberwise init
        let properties = parseProperties(from: structDecl)

        // Check if there are any CLI properties
        let hasCLIProperties = properties.contains { prop in
            if case .none = prop.attribute { return false }
            return true
        }

        // For namespace commands (no CLI properties), don't generate an initializer
        // Swift will provide a default parameterless initializer
        if !hasCLIProperties {
            return []
        }

        // Generate initializer for commands with properties
        let initDecl = generateInitializer(properties: properties)

        return [DeclSyntax(initDecl)]
    }

    // MARK: - Helpers

    private static func extractExplicitName(from node: AttributeSyntax) -> String? {
        guard let arguments = node.arguments?.as(LabeledExprListSyntax.self) else {
            return nil
        }

        // Look for labeled "name:" argument or unlabeled first string argument
        for arg in arguments {
            if let stringLiteral = arg.expression.as(StringLiteralExprSyntax.self),
               let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
                return segment.content.text
            }
        }
        return nil
    }

    /// Extract the full command chain from lexical context
    /// Returns an array of CommandInfo from root (program) to immediate parent
    private static func extractCommandChain(from context: some MacroExpansionContext) -> [CommandInfo] {
        var chain: [CommandInfo] = []

        for lexicalContext in context.lexicalContext {
            if let structDecl = lexicalContext.as(StructDeclSyntax.self) {
                // Check what attributes this struct has
                var isProgram = false
                var isCommand = false
                var explicitName: String? = nil

                for attr in structDecl.attributes {
                    guard let attrSyntax = attr.as(AttributeSyntax.self),
                          let identifier = attrSyntax.attributeName.as(IdentifierTypeSyntax.self) else {
                        continue
                    }

                    let attrName = identifier.name.text
                    if attrName == "CLIProgram" {
                        isProgram = true
                        explicitName = extractExplicitNameFromAttribute(attrSyntax)
                    } else if attrName == "CLICommand" {
                        isCommand = true
                        explicitName = extractExplicitNameFromAttribute(attrSyntax)
                    }
                }

                // Only include structs with @CLIProgram or @CLICommand
                if isProgram || isCommand {
                    let commandName = explicitName ?? toKebabCase(structDecl.name.text)
                    chain.append(CommandInfo(
                        typeName: structDecl.name.text,
                        commandName: commandName,
                        isProgram: isProgram
                    ))
                }
            }
        }

        // The lexical context is from innermost to outermost, so reverse it
        // to get root (program) first
        return chain.reversed()
    }

    /// Extract explicit name from an attribute syntax node
    private static func extractExplicitNameFromAttribute(_ attr: AttributeSyntax) -> String? {
        guard let arguments = attr.arguments?.as(LabeledExprListSyntax.self) else {
            return nil
        }

        for arg in arguments {
            if let stringLiteral = arg.expression.as(StringLiteralExprSyntax.self),
               let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
                return segment.content.text
            }
        }
        return nil
    }
}

// MARK: - Property Parsing

struct ParsedProperty {
    let name: String
    let type: String
    let isOptional: Bool
    let hasDefault: Bool
    let defaultValue: String?
    let attribute: PropertyAttribute
}

enum PropertyAttribute {
    /// Flag with explicit names (can be empty for inferred, one name, or two names)
    case flag(names: [String])
    /// Option with explicit names (can be empty for inferred, one name, or two names)
    case option(names: [String])
    /// Prefix option where prefix and value are joined (e.g., -9 for kill)
    case prefixOption(prefix: String)
    case positional
    case none
}

func parseProperties(from structDecl: StructDeclSyntax) -> [ParsedProperty] {
    var properties: [ParsedProperty] = []

    for member in structDecl.memberBlock.members {
        guard let varDecl = member.decl.as(VariableDeclSyntax.self),
              let binding = varDecl.bindings.first,
              let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else {
            continue
        }

        let name = pattern.identifier.text

        // Get type info
        var typeString = "String"
        var isOptional = false

        if let typeAnnotation = binding.typeAnnotation {
            let type = typeAnnotation.type
            if let optionalType = type.as(OptionalTypeSyntax.self) {
                isOptional = true
                typeString = optionalType.wrappedType.description.trimmingCharacters(in: .whitespaces)
            } else {
                typeString = type.description.trimmingCharacters(in: .whitespaces)
            }
        }

        // Check for default value
        let hasDefault = binding.initializer != nil
        var defaultValue: String? = nil
        if let initializer = binding.initializer {
            defaultValue = initializer.value.description.trimmingCharacters(in: .whitespaces)
        }

        // Parse attribute
        let attribute = parseAttribute(from: varDecl)

        properties.append(ParsedProperty(
            name: name,
            type: typeString,
            isOptional: isOptional,
            hasDefault: hasDefault,
            defaultValue: defaultValue,
            attribute: attribute
        ))
    }

    return properties
}

func parseAttribute(from varDecl: VariableDeclSyntax) -> PropertyAttribute {
    for attr in varDecl.attributes {
        guard let attribute = attr.as(AttributeSyntax.self),
              let identifier = attribute.attributeName.as(IdentifierTypeSyntax.self) else {
            continue
        }

        let attrName = identifier.name.text

        switch attrName {
        case "Flag":
            let names = parseVariadicStringArgs(from: attribute)
            return .flag(names: names)

        case "Option":
            let names = parseVariadicStringArgs(from: attribute)
            return .option(names: names)

        case "PrefixOption":
            let args = parseVariadicStringArgs(from: attribute)
            let prefix = args.first ?? "-"
            return .prefixOption(prefix: prefix)

        case "Positional":
            return .positional

        default:
            continue
        }
    }

    return .none
}

/// Parse variadic string arguments from an attribute
/// Handles: @Flag, @Flag("-f"), @Flag("--force", "-f")
func parseVariadicStringArgs(from attribute: AttributeSyntax) -> [String] {
    guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self) else {
        return []
    }

    var names: [String] = []

    for arg in arguments {
        if let stringLiteral = arg.expression.as(StringLiteralExprSyntax.self),
           let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
            names.append(segment.content.text)
        }
    }

    return names
}

// MARK: - Code Generation

func generateArgumentsCode(properties: [ParsedProperty]) -> String {
    var lines: [String] = []

    // First add flags and options, then positionals
    for prop in properties {
        switch prop.attribute {
        case .flag(let names):
            // Determine the flag name to use:
            // - Empty names: infer from property name (--kebab-case)
            // - One name: use that exact name
            // - Two names: use the first (long form)
            let flagName: String
            if names.isEmpty {
                flagName = "--\(toKebabCase(prop.name))"
            } else {
                flagName = names[0]
            }
            lines.append("if self.\(prop.name) { args.append(.flag(CLIFlag(\"\(flagName)\"))) }")

        case .option(let names):
            // Determine the option name to use:
            // - Empty names: infer from property name (--kebab-case)
            // - One name: use that exact name
            // - Two names: use the first (long form)
            let optionName: String
            if names.isEmpty {
                optionName = "--\(toKebabCase(prop.name))"
            } else {
                optionName = names[0]
            }
            // Check if this is an array type (variadic option like --context foo --context bar)
            let isArray = prop.type.hasPrefix("[") && prop.type.hasSuffix("]")
            if isArray {
                // For array options, iterate and add each element with the same flag
                lines.append("for value in self.\(prop.name) { args.append(.option(CLIOption(\"\(optionName)\", value: value))) }")
            } else if prop.isOptional {
                lines.append("if let value = self.\(prop.name) { args.append(.option(CLIOption(\"\(optionName)\", value: value))) }")
            } else {
                lines.append("args.append(.option(CLIOption(\"\(optionName)\", value: self.\(prop.name))))")
            }

        case .prefixOption(let prefix):
            // Prefix option joins prefix and value (e.g., -9 for kill)
            if prop.isOptional {
                lines.append("if let value = self.\(prop.name) { args.append(.prefixOption(CLIPrefixOption(\"\(prefix)\", value: value))) }")
            } else {
                lines.append("args.append(.prefixOption(CLIPrefixOption(\"\(prefix)\", value: self.\(prop.name))))")
            }

        case .positional:
            // Check if this is an array type (e.g., [String])
            let isArray = prop.type.hasPrefix("[") && prop.type.hasSuffix("]")
            if isArray {
                // For array positionals, iterate and add each element
                lines.append("for value in self.\(prop.name) { args.append(.positional(CLIPositional(value))) }")
            } else if prop.isOptional {
                lines.append("if let value = self.\(prop.name) { args.append(.positional(CLIPositional(value))) }")
            } else {
                lines.append("args.append(.positional(CLIPositional(self.\(prop.name))))")
            }

        case .none:
            continue
        }
    }

    return lines.joined(separator: "\n        ")
}

func generateInitializer(properties: [ParsedProperty]) -> InitializerDeclSyntax {
    // Build parameter list
    var params: [String] = []

    for prop in properties {
        // Skip properties without CLI attributes
        guard case .none = prop.attribute else {
            let paramType = prop.isOptional ? "\(prop.type)?" : prop.type
            // Check if this is an array type
            let isArray = prop.type.hasPrefix("[") && prop.type.hasSuffix("]")
            if let defaultValue = prop.defaultValue {
                params.append("\(prop.name): \(paramType) = \(defaultValue)")
            } else if prop.isOptional {
                params.append("\(prop.name): \(paramType) = nil")
            } else if isArray {
                // For array types without a default, default to empty array
                params.append("\(prop.name): \(paramType) = []")
            } else {
                params.append("\(prop.name): \(paramType)")
            }
            continue
        }
    }

    // Build assignments
    var assignments: [String] = []
    for prop in properties {
        guard case .none = prop.attribute else {
            assignments.append("self.\(prop.name) = \(prop.name)")
            continue
        }
    }

    let paramList = params.joined(separator: ", ")
    let bodyStatements = assignments.joined(separator: "\n        ")

    return try! InitializerDeclSyntax("public init(\(raw: paramList))") {
        "\(raw: bodyStatements)"
    }
}
