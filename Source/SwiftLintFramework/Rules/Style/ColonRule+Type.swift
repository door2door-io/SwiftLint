import Foundation
import SourceKittenFramework

internal extension ColonRule {
    var pattern: String {
        // If flexible_right_spacing is true, match only 0 whitespaces.
        // If flexible_right_spacing is false or omitted, match 0 or 2+ whitespaces.
        let spacingRegex = configuration.flexibleRightSpacing ? "(?:\\s{0})" : "(?:\\s{0}|\\s{2,})"

        return "(\\w)" +       // Capture an identifier
            "(?:" +         // start group
            "\\s+" +        // followed by whitespace
            ":" +           // to the left of a colon
            "\\s*" +        // followed by any amount of whitespace.
            "|" +           // or
            ":" +           // immediately followed by a colon
            spacingRegex +  // followed by right spacing regex
            ")" +           // end group
            "(" +           // Capture a type identifier
            "[\\[|\\(]*" +  // which may begin with a series of nested parenthesis or brackets
        "\\S)"          // lazily to the first non-whitespace character.
    }

    func typeColonViolationRanges(in file: File, matching pattern: String) -> [NSRange] {
        let nsstring = file.contents.bridge()
        let commentAndStringKindsSet = SyntaxKind.commentAndStringKinds
        return file.rangesAndTokens(matching: pattern).filter { _, syntaxTokens in
            let syntaxKinds = syntaxTokens.compactMap { SyntaxKind(rawValue: $0.type) }

            guard syntaxKinds.count == 2 else {
                return false
            }

            if !configuration.applyToDictionaries {
                let (leftColonSideToken, rightColonSideToken) = (syntaxTokens[0], syntaxTokens[1])
                let bothTokensAreTypeIdentifiers: Bool
                switch (syntaxKinds[0], syntaxKinds[1]) {
                case (.typeidentifier, .typeidentifier):
                    bothTokensAreTypeIdentifiers = true
                case (.typeidentifier, .keyword):
                    bothTokensAreTypeIdentifiers = file.isTypeLike(token: rightColonSideToken)
                default:
                    bothTokensAreTypeIdentifiers = false
                }
                
                if bothTokensAreTypeIdentifiers {
                    let openBracketCandidate = nsstring.firstNonWhitespaceCharacter(beforeCharacterAt: leftColonSideToken.offset)
                    let closingBracketCandidate = nsstring.firstNonWhitespaceCharacter(afterCharacterAt: rightColonSideToken.offset + rightColonSideToken.length - 1)
                    switch (openBracketCandidate, closingBracketCandidate) {
                    case (.some("["), .some("]")):
                        // Matching pattern is a dictionary type declaration which should be ignored because
                        // apply_to_dictionaries configurable flag is disabled
                        return false
                    default:
                        break
                    }
                }
            }
            
            let validKinds: Bool
            switch (syntaxKinds[0], syntaxKinds[1]) {
            case (.identifier, .typeidentifier),
                 (.typeidentifier, .typeidentifier):
                validKinds = true
            case (.identifier, .keyword),
                 (.typeidentifier, .keyword):
                validKinds = file.isTypeLike(token: syntaxTokens[1])
            case (.keyword, .typeidentifier):
                validKinds = file.isTypeLike(token: syntaxTokens[0])
            default:
                validKinds = false
            }

            guard validKinds else {
                return false
            }

            return Set(syntaxKinds).isDisjoint(with: commentAndStringKindsSet)
        }.compactMap { range, syntaxTokens in
            let identifierRange = nsstring
                .byteRangeToNSRange(start: syntaxTokens[0].offset, length: 0)
            return identifierRange.map { NSUnionRange($0, range) }
        }
    }
    
}

private extension File {
    func isTypeLike(token: SyntaxToken) -> Bool {
        let nsstring = contents.bridge()
        guard let text = nsstring.substringWithByteRange(start: token.offset, length: token.length),
            let firstLetter = text.unicodeScalars.first else {
                return false
        }

        return CharacterSet.uppercaseLetters.contains(firstLetter)
    }
}


private extension NSString {
    
    func firstNonWhitespaceCharacter(beforeCharacterAt index: Int) -> Unicode.Scalar? {
        var _index = index - 1
        let whitespace: Unicode.Scalar = " "
        while index > 0 && index < self.length {
            if let character = Unicode.Scalar(self.character(at: _index)), character != whitespace {
                return character
            }
            _index -= 1
        }
        return .none
    }
    
    func firstNonWhitespaceCharacter(afterCharacterAt index: Int) -> Unicode.Scalar? {
        var _index = index + 1
        let whitespace: Unicode.Scalar = " "
        while index < self.length {
            if let character = Unicode.Scalar(self.character(at: _index)), character != whitespace {
                return character
            }
            _index += 1
        }
        return .none
    }
    
}
