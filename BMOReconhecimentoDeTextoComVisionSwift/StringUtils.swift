//
//  StringUtils.swift
//  BMOReconhecimentoDeTextoComVisionSwift
//
//  Created by Breno Medeiros on 09/07/20.
//  Copyright © 2020 ProgramasBMO. All rights reserved.
//

import Foundation


extension Character {
    // Dada uma lista de caracteres permitidos, tenta converter aqueles da lista
    // se ainda não estiver nele. Isso lida com alguns erros de classificação comuns para
    // caracteres visualmente semelhantes e que só podem ser reconhecidos corretamente
    // com mais conhecimento de contexto e / ou domínio. Alguns exemplos (devem ser lidos
    // no Menlo ou em outra fonte com símbolos diferentes para todos os caracteres):
    // 1 e I temos o mesmo caractere em Times New Roman
    // I e l são o mesmo caractere em Helvetica
    // 0 e O são extremamente semelhantes em muitas fontes
    // oO, wW, cC, sS, pP e outros diferem apenas em tamanho em muitas fontes
    func getSimilarCharacterIfNotIn(allowedChars: String) -> Character {
        let conversionTable = [
            "s": "S",
            "S": "5",
            "5": "S",
            "o": "O",
            "Q": "O",
            "O": "0",
            "0": "O",
            "l": "I",
            "I": "1",
            "1": "I",
            "B": "8",
            "8": "B"
        ]
        // Permite no máximo duas substituições para manipular 's' -> 'S' -> '5'.
        let maxSubstitutions = 2
        var current = String(self)
        var counter = 0
        while !allowedChars.contains(current) && counter < maxSubstitutions {
            if let altChar = conversionTable[current] {
                current = altChar
                counter += 1
            } else {
                // Não bate com nada da tabela. Desiste.
                break
            }
        }
        
        return current.first!
    }
}

extension String {
    // Extrai o primeiro número de telefone no estilo americano encontrado na string, retornando
    // o intervalo do número e o próprio número como uma tupla.
    // Retorna nil se nenhum número for encontrado.
    func extractPhoneNumber() -> (Range<String.Index>, String)? {
        // Faz um primeiro passo para encontrar qualquer substring que possa ser um telefone dos EUA
        // Isso corresponderá aos seguintes padrões comuns e muito mais:
        // xxx-xxx-xxxx
        // xxx xxx xxxx
        // (xxx) xxx-xxxx
        // (xxx) xxx-xxxx
        // xxx.xxx.xxxx
        // xxx xxx-xxxx
        // xxx / xxx.xxxx
        // + 1-xxx-xxx-xxxx
        // Observe que isso não procura apenas dígitos, pois alguns dígitos parecem
        // muito parecido com letras. Isso é tratado mais tarde.
        let pattern = #"""
        (?x)                    # Verbose regex, allows comments
        (?:\+1-?)?                # Potential international prefix, may have -
        [(]?                    # Potential opening (
        \b(\w{3})                # Capture xxx
        [)]?                    # Potential closing )
        [\ -./]?                # Potential separator
        (\w{3})                    # Capture xxx
        [\ -./]?                # Potential separator
        (\w{4})\b                # Capture xxxx
        """#
        
        guard let range = self.range(of: pattern, options: .regularExpression, range: nil, locale: nil) else {
            // Nenhum telefone encontrado.
            return nil
        }
        
        // Potencial numero encontrado. Retire a pontuação, espaço em branco e prefixo do país
        var phoneNumberDigits = ""
        let substring = String(self[range])
        let nsrange = NSRange(substring.startIndex..., in: substring)
        do {
            // Extrai os caracteres da substring.
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            if let match = regex.firstMatch(in: substring, options: [], range: nsrange) {
                for rangeInd in 1 ..< match.numberOfRanges {
                    let range = match.range(at: rangeInd)
                    let matchString = (substring as NSString).substring(with: range)
                    phoneNumberDigits += matchString as String
                }
            }
        } catch {
            print("Error \(error) when creating pattern")
        }
        
        // Deve ter exatamente 10 dígitos.
        guard phoneNumberDigits.count == 10 else {
            return nil
        }
        
        // Substitua caracteres comumente mal reconhecidos, por exemplo: 'S' -> '5' ou 'l' -> '1'
        var result = ""
        let allowedChars = "0123456789()-_"
        for var char in phoneNumberDigits {
            char = char.getSimilarCharacterIfNotIn(allowedChars: allowedChars)
            guard allowedChars.contains(char) else {
                return nil
            }
            result.append(char)
        }
        return (range, result)
    }
}

class StringTracker {
    var frameIndex: Int64 = 0

    typealias StringObservation = (lastSeen: Int64, count: Int64)
    
    // Dicionário de strings vistas/conhecidas. Usado para obter
    // reconhecimento estável antes de exibir qualquer coisa.
    var seenStrings = [String: StringObservation]()
    var bestCount = Int64(0)
    var bestString = ""

    func logFrame(strings: [String]) {
        for string in strings {
            if seenStrings[string] == nil {
                seenStrings[string] = (lastSeen: Int64(0), count: Int64(-1))
            }
            seenStrings[string]?.lastSeen = frameIndex
            seenStrings[string]?.count += 1
            print("Seen \(string) \(seenStrings[string]?.count ?? 0) times")
        }
    
        var obsoleteStrings = [String]()

        // Passa pelas Strings e poda(=corta partes inuteis) as que não foram vistas há algum tempo.
        // Encontra também a string (não podada) com a maior contagem.
        for (string, obs) in seenStrings {
            // Remova o texto visto anteriormente após 30 quadros (~ 1s).
            if obs.lastSeen < frameIndex - 30 {
                obsoleteStrings.append(string)
            }
            
            // Encontre a string com a maior contagem.
            let count = obs.count
            if !obsoleteStrings.contains(string) && count > bestCount {
                bestCount = Int64(count)
                bestString = string
            }
        }
        // Remova as strings antigas.
        for string in obsoleteStrings {
            seenStrings.removeValue(forKey: string)
        }
        
        frameIndex += 1
    }
    
    func getStableString() -> String? {
        // Exije que o reconhecedor veja a mesma sequência pelo menos 10 vezes.
        if bestCount >= 10 {
            return bestString
        } else {
            return nil
        }
    }
    
    func reset(string: String) {
        seenStrings.removeValue(forKey: string)
        bestCount = 0
        bestString = ""
    }
}
