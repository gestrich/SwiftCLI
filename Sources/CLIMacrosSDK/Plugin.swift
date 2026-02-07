import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct SdkCliMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        CLICommandMacro.self,
        CLIProgramMacro.self,
        FlagMacro.self,
        OptionMacro.self,
        PositionalMacro.self,
        PrefixOptionMacro.self,
    ]
}
