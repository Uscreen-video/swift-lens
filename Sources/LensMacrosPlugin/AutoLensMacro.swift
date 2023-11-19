import SwiftDiagnostics
import SwiftOperators
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros

public struct AutoLensMacro: MemberMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingMembersOf declaration: some DeclGroupSyntax,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    guard let declaration = declaration.as(StructDeclSyntax.self)
    else {
      context.diagnose(
        Diagnostic(
          node: declaration,
          message: MacroExpansionErrorMessage(
            "'@AutoLens' can only be applied to struct types"
          )
        )
      )
      return []
    }
    
    let members = declaration.memberBlock.members
    
    let properties = members.reduce(into: [Property]()) { buffer, member in
      guard 
        let property = member.decl.as(VariableDeclSyntax.self),
        let binding = property.bindings.first,
        let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
        let type = binding.typeAnnotation?.type ?? binding.initializer?.value.literalType
      else { return }
      let propertyAccess = Access(modifiers: property.modifiers) ?? .private
      buffer.append(Property(declaration: property, identifier: identifier, access: propertyAccess, type: type))
    }
    
    var declSyntax: [any DeclSyntaxProtocol] = []
    
    // Adding initializer
    
    let existedInitializers = declaration.memberBlock.members.compactMap { $0.decl.as(InitializerDeclSyntax.self) }
    let initializer = try initializerDeclaration(for: properties)
    
    let sameInitializer = existedInitializers.isEmpty
    ? nil
    : existedInitializers.first(where: { $0.signature.isSame(as: initializer.signature) })
    
    let haveNoSameInitializer = sameInitializer == nil
    
    let usableInitializer = sameInitializer ?? initializer
    
    // Adding subscript
    declSyntax.append(try addSubscript(in: declaration))
    
    if haveNoSameInitializer {
      declSyntax.append(initializer)
    }
    
    // Adding lenses
    
    let lenses = try properties.filter { $0.access == .public }.map { try Self.lens(for: $0, with: usableInitializer, in: declaration) }
    let enumDecl = try Self.embedLenses(lenses, for: properties, in: declaration)
    
    declSyntax.append(enumDecl)
    
    let formatted = declSyntax.map { $0.formatted() }.compactMap { DeclSyntax($0) }
    
    return formatted
  }
  
  private static func addSubscript(in structDecl: StructDeclSyntax) throws -> SubscriptDeclSyntax {
    let structName = structDecl.name.text
    return try SubscriptDeclSyntax(
      """
      public static subscript<T>(lens path: KeyPath<\(raw: structName), T>) -> Lens<\(raw: structName), T> {
        let anyLens = AllLenses.lensesDictionary[ObjectIdentifier(path)]
        return anyLens as! Lens<\(raw: structName), T>
      }
      """
    )
  }
  
  private static func embedLenses(_ lenses: [VariableDeclSyntax], for properties: [Property], in structDecl: StructDeclSyntax) throws -> EnumDeclSyntax {
    let structName = structDecl.name.text
    let publicProperties = properties.filter { $0.access == .public }
    let dictionaryDecl = try VariableDeclSyntax(
      """
      fileprivate static var lensesDictionary: [AnyHashable: Any] {
        [\n\(raw: publicProperties.isEmpty ? "[:]" : publicProperties.map(\.identifierName)
          .map { name in
            let pathStr = "\(structName).\(name)"
            return "ObjectIdentifier(\\\(pathStr)): AllLenses.\(name)"
          }.joined(separator: ",\n")
        )\n]
      }
      """
    )
    .formatted()
    
    return try EnumDeclSyntax(
      """
      enum AllLenses {
        \(raw: lenses.map { $0.formatted() }.map(\.description).joined(separator: "\n\n"))
      
        \(dictionaryDecl)
      }
      """
    )
  }
  
  private static func lens(for property: Property, with initializer: InitializerDeclSyntax, in structDecl: StructDeclSyntax) throws -> VariableDeclSyntax {
    let parameters = initializer.signature.parameterClause
      .parameters.map(\.firstName.text)
      .map { name in
        return if name == property.identifierName {
          "\(name): target"
        } else {
          "\(name): whole.\(name)"
        }
      }
      .joined(separator: ",\n")
    
    let structName = structDecl.name.text
    
    let initializerCall = ExprSyntax(
      "\(raw: structName)(\n\(raw: parameters)\n)"
    )
    
    let lens = try VariableDeclSyntax(
      """
      public static let \(raw: property.identifierName) = Lens<\(raw: structName), \(raw: property.typeName)>(
        get: { whole in
          whole.\(raw: property.identifierName)
        },
        set: { whole, target in
          \(initializerCall)
        }
      )
      """
    )
    
    return lens
  }
  
  private static func initializerDeclaration(for properties: [Property]) throws -> InitializerDeclSyntax {
    let namesAndTypes = properties.map { "\($0.identifier): \($0.typeName)" }.joined(separator: ",\n")
    
    var nodeString = "private init(\n"
    nodeString += namesAndTypes
    nodeString += "\n)"
    
    let syntax = try InitializerDeclSyntax(SyntaxNodeString(stringLiteral: nodeString)) {
      for name in properties.map(\.identifier) {
        ExprSyntax("self.\(name) = \(name)")
      }
    }
    
    return try InitializerDeclSyntax(validating: syntax)
  }
}

extension VariableDeclSyntax {
  var asClosureType: FunctionTypeSyntax? {
    self.bindings.first?.typeAnnotation.flatMap {
      $0.type.as(FunctionTypeSyntax.self)
        ?? $0.type.as(AttributedTypeSyntax.self)?.baseType.as(FunctionTypeSyntax.self)
    }
  }

  var isClosure: Bool {
    self.asClosureType != nil
  }
}

enum AutoLensMacroDiagnostic {
  case typeIsNotStructOrClass(DeclGroupSyntax)
}

extension AutoLensMacroDiagnostic: DiagnosticMessage {
  var message: String {
    switch self {
    case let .typeIsNotStructOrClass(decl):
      return """
      @AutoLens cannot be applied to\
      \(decl.keywordDescription.map { " \($0)" } ?? "")
      """
    }
  }
  
  var diagnosticID: SwiftDiagnostics.MessageID {
    switch self {
    case .typeIsNotStructOrClass:
      return MessageID(domain: "MetaTypeDiagnostic", id: "typeIsNotStructOrClass")
    }
  }
  
  var severity: SwiftDiagnostics.DiagnosticSeverity {
    switch self {
    case .typeIsNotStructOrClass:
      return .error
    }
  }
}

private enum Access: Comparable {
  case `private`
  case `internal`
  case `public`

  init?(modifiers: DeclModifierListSyntax) {
    for modifier in modifiers {
      switch modifier.name.tokenKind {
      case .keyword(.private):
        self = .private
        return
      case .keyword(.internal):
        self = .internal
        return
      case .keyword(.public):
        self = .public
        return
      default:
        continue
      }
    }
    return nil
  }
}

extension DeclGroupSyntax {
  var keywordDescription: String? {
    switch self {
    case let syntax as ActorDeclSyntax:
      return syntax.actorKeyword.trimmedDescription
    case let syntax as ClassDeclSyntax:
      return syntax.classKeyword.trimmedDescription
    case let syntax as ExtensionDeclSyntax:
      return syntax.extensionKeyword.trimmedDescription
    case let syntax as ProtocolDeclSyntax:
      return syntax.protocolKeyword.trimmedDescription
    case let syntax as StructDeclSyntax:
      return syntax.structKeyword.trimmedDescription
    case let syntax as EnumDeclSyntax:
      return syntax.enumKeyword.trimmedDescription
    default:
      return nil
    }
  }
}

private struct Property {
  let declaration: VariableDeclSyntax
  let identifier: IdentifierPatternSyntax
  let access: Access
  let type: TypeSyntax
  
  var identifierName: String {
    identifier.identifier.text
  }
  
  var typeName: String {
    type.trimmedDescription
  }
}

extension ExprSyntax {
  fileprivate var literalType: TypeSyntax? {
    if self.is(BooleanLiteralExprSyntax.self) {
      return "Swift.Bool"
    } else if self.is(FloatLiteralExprSyntax.self) {
      return "Swift.Double"
    } else if self.is(IntegerLiteralExprSyntax.self) {
      return "Swift.Int"
    } else if self.is(StringLiteralExprSyntax.self) {
      return "Swift.String"
    } else {
      return nil
    }
  }
}

extension FunctionSignatureSyntax {
  func isSame(as other: FunctionSignatureSyntax) -> Bool {
    let parameter = self.parameterClause.parameters
    let otherParameter = other.parameterClause.parameters
    
    if parameter.count != otherParameter.count {
      return false
    }
    
    let names = parameter.map(\.firstName.text)
    let otherNames = otherParameter.map(\.firstName.text)
    
    let types = parameter.map(\.type.trimmedDescription)
    let otherTypes = otherParameter.map(\.type.trimmedDescription)
    
    if names == otherNames && types == otherTypes {
      return true
    }
    
    return false
  }
}
