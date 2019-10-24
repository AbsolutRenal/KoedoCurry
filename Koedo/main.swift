//
//  main.swift
//  Koedo
//
//  Created by Renaud Cousin on 10/21/19.
//  Copyright © 2019 AbsolutRenal. All rights reserved.
//

import Cocoa
import Foundation

enum KoedoError: Error {
    case invalidURL
    case invalidWebsiteSourceFormat
}

enum Constants {
    static let meal = "curry"
    static let dishSearchTagRef = "fp_price"
    static let dishSplitStartTagRef = "title='"
    static let dishSplitEndTagRef = "'"
    static let daySearchTagRef = "primary_type"
    static let daySplitStartTagRef = "data-name='*** "
    static let daySplitEndTagRef = " ***"
    static let urlString = "https://koedo.fr/"
}

enum Day: String {
    case monday = "lundi"
    case tuesday = "mardi"
    case wednesday = "mercredi"
    case thursday = "jeudi"
    case friday = "vendredi"

    init?(withWeekDay weekDay: Int) {
        switch weekDay {
        case 2:
            self = .monday
        case 3:
            self = .tuesday
        case 4:
            self = .wednesday
        case 5:
            self = .thursday
        case 6:
            self = .friday
        default:
            return nil
        }
    }
}

enum HtmlTagType {
    case day(String)
    case dish(String)

    func isKindOf(_ type: HtmlTagType) -> Bool {
        switch (self, type) {
        case (.day, .day), (.dish, .dish): return true
        default: return false
        }
    }
}

struct MealDay {
    let day: String
    let dishType: String
}

typealias KoedoMenu = [Day: [String]]
extension KoedoMenu {
    func menu(forDay day: Day) -> String {
        let dayMenu = self[day]
        let menuString = "\n-- \(day.rawValue):\n\(dayMenu!.joined(separator: "\n"))\n"
        return menuString
    }

    func searchMeal(_ meal: String, time: ArgumentType) -> [MealDay] {
        switch time {
        case .week:
            return searchMeal(meal, in: self)
        case .day(let weekDay):
            let filtererDayMenu = self.filter { $0.key == weekDay }
            return searchMeal(meal, in: filtererDayMenu)
        default:
            return []
        }
    }

    private func searchMeal(_ meal: String, in menu: KoedoMenu) -> [MealDay] {
        var mealDays = [MealDay]()
        menu.forEach { key, value in
            let searchedMeal = value.filter({ dish in
                return dish.lowercased().contains(meal)
            })
            mealDays.append(contentsOf: searchedMeal.map { MealDay(day: key.rawValue, dishType: $0) })
        }
        return mealDays
    }
}

final class KoedoMenuFetcher {
    // MARK: Public
    func fetchMenu() throws -> KoedoMenu {
        let sources = try fetchWebSite()
        return parseSources(sources)
    }

    // MARK: Private
    private func fetchWebSite() throws -> String {
        guard let url = URL(string: Constants.urlString) else {
            throw KoedoError.invalidURL
        }
        let group = DispatchGroup()
        var source: String = ""
        var sourceError: Error?
        let request = URLRequest(url: url)
        group.enter()
        URLSession.shared.dataTask(with: request) { data, response, error in
            defer {
                group.leave()
            }
            guard error == nil else {
                sourceError = error
                return
            }
            guard let data = data,
                let str = String(data: data, encoding: .utf8) else {
                    sourceError = KoedoError.invalidWebsiteSourceFormat
                    return
            }
            source = str

            }.resume()
        group.wait()

        if let sourceError = sourceError {
            throw sourceError
        }
        return source
    }

    private func parseSources(_ sources: String) -> KoedoMenu {
        let tags = removeUselessHtmlTags(from: sources)
        var menu = extractMenu(from: tags)
        validateMenuOrder(&menu)
        return processMenu(menu)
    }

    private func removeUselessHtmlTags(from source: String) -> [String] {
        let processed = source.components(separatedBy: "<div")
        let filtered = processed.filter {
            isDayTag($0) || isDishTag($0)
        }
        return filtered
    }

    private func isDayTag(_ tag: String) -> Bool {
        return tag.contains(Constants.daySearchTagRef)
    }

    private func isDishTag(_ tag: String) -> Bool {
        return tag.contains(Constants.dishSearchTagRef)
    }

    private func extractMenu(from tags: [String]) -> [HtmlTagType] {
        return tags.compactMap {
            if isDayTag($0) {
                return extractDayName(from: $0)
            } else if isDishTag($0) {
                return extractDishName(from: $0)
            }
            return nil
        }
    }

    private func extractDayName(from tag: String) -> HtmlTagType? {
        guard let dayString = processTag(tag,
                                         withStartPattern: Constants.daySplitStartTagRef,
                                         endPattern: Constants.daySplitEndTagRef) else {
                                            return nil
        }
        return .day(dayString)
    }

    private func extractDishName(from tag: String) -> HtmlTagType? {
        guard let dishString = processTag(tag,
                                          withStartPattern: Constants.dishSplitStartTagRef,
                                          endPattern: Constants.dishSplitEndTagRef) else {
                                            return nil
        }
        return .dish(dishString)
    }

    private func processTag(_ tag: String, withStartPattern startattern: String, endPattern: String) -> String? {
        let arr = tag.components(separatedBy: startattern)
        guard arr.count == 2 else {
            return nil
        }
        let arr2 = arr[1].components(separatedBy: endPattern)
        return arr2.first
    }

    private func validateMenuOrder(_ menu: inout [HtmlTagType]) {
        guard menu.first(where: { $0.isKindOf(.day("")) }) != nil else {
            return
        }
        while !menu[0].isKindOf(.day("")) {
            menu.removeFirst()
        }
    }

    private func processMenu(_ menu: [HtmlTagType]) -> KoedoMenu {
        var currentDay: Day?
        var processedMenu: KoedoMenu = [:]
        for (_, value) in menu.enumerated() {
            switch value {
            case .day(let dayString):
                currentDay = Day(rawValue: dayString.lowercased())
                guard let currentDay = currentDay else {
                    continue
                }
                processedMenu[currentDay] = []
            case .dish(let dishName) where currentDay != nil:
                processedMenu[currentDay!]!.append(dishName)
            default:
                break
            }
        }
        return processedMenu
    }
}

enum ArgumentType {
    case day(Day)
    case week
    case meal(String)
    case order
    case help
    case unknown(String)
    case malformed(String)

    var isTemporalConstraint: Bool {
        return self.isKindOf(.day(.monday)) || self.isKindOf(.week)
    }

    var isStandAloneInstruction: Bool {
        return self.isKindOf(.help) || self.isKindOf(.order)
    }

    init(with value: String, arguments: [String]? = nil) {
        switch value {
            case "--meal" where arguments?.count == 1,
                 "-m" where arguments?.count == 1:
                    self = .meal(arguments!.first!)
        case "--week", "-w":
            self = .week
        case "--today", "-t":
            guard let today = Calendar.current.dateComponents([.weekday], from: Date()).weekday,
                let day = Day(withWeekDay: today) else {
                    self = .unknown("Unable to get menu day. Koedo is not open during week end")
                    return
            }
            self = .day(day)
        case "--order", "-o":
            self = .order
        case "--help", "-h":
            self = .help
        default:
            self = .unknown(value)
        }
    }

    func isKindOf(_ type: ArgumentType) -> Bool {
        switch (self, type) {
        case (.day, .day),
             (.week, .week),
             (.meal, .meal),
             (.order, .order),
             (.help, .help),
             (.unknown, .unknown),
             (.malformed, .malformed):
            return true
        default:
            return false
        }
    }

    static func numberOfExtraArgumentsNeeded(for argStr: String) -> Int {
        switch argStr {
        case "--meal", "-m":
            return 1
        default:
            return 0
        }
    }

    static func isArgument(_ string: String) -> Bool {
        return ["-t", "--today", "-w", "--week", "-h", "--help", "-o", "--order", "-m", "--meal"].contains(string)
    }

    static var usage: String = """
                                Usage: koedo [OPTIONS] [ARGS]

                                Utility to look at Koedo (https://koedo.fr) menu, or simply search
                                for a special meal in the week.

                                Options:
                                --meal, -m MEAL     Search for a specific MEAL in the menu
                                --today, -t         Show today's menu
                                --week, -w          Show week's menu
                                --order, -o         Open Safari webpage to order
                                --help, -h          Show this message and exit
                                """

}

final class CommandLineArgumentsParser {
    // MARK: Public
    var temporalConstraint: ArgumentType {
        return query.first(where: { $0.isTemporalConstraint}) ?? .week
    }

    // MARK: Private
    private(set) var query: [ArgumentType]

    // MARK: Lifecycle
    init(with args: [String]) {
        var receivedArguments = [ArgumentType]()
        var mutableArgs = [String](args)
        var currentArg: String
        var extraArguments: [String]?
        while mutableArgs.count > 0 {
            currentArg = mutableArgs.removeFirst()

            if case let extraArgumentsCount = ArgumentType.numberOfExtraArgumentsNeeded(for: currentArg), extraArgumentsCount > 0 {
                extraArguments = []
                guard mutableArgs.count >= extraArgumentsCount else {
                    receivedArguments.append(ArgumentType.malformed("\(currentArg) need \(extraArgumentsCount) extra arguments, have only \(mutableArgs.count)"))
                    mutableArgs.removeAll()
                    break
                }
                for _ in 0..<extraArgumentsCount {
                    guard !ArgumentType.isArgument(mutableArgs.first!) else {
                        receivedArguments.append(ArgumentType.malformed("\(currentArg) need \(extraArgumentsCount) extra arguments, have only \(mutableArgs.count - 1)"))
                        mutableArgs.removeAll()
                        self.query = receivedArguments
                        return
                    }
                    extraArguments?.append(mutableArgs.removeFirst())
                }
            } else {
                extraArguments = nil
            }
            receivedArguments.append(ArgumentType(with: currentArg, arguments: extraArguments))
        }
        self.query = receivedArguments
    }

    // MARK: public
    func validateQuery() throws {
        if query.isEmpty {
            throw ArgumentsError.emptyQuery
        }
        if case let unknownArguments = query.filter({ $0.isKindOf(.unknown("")) }),
            unknownArguments.count > 0 {
                throw ArgumentsError.unknownArguments(unknownArguments)
        }
        if case let malformedArguments = query.filter({ $0.isKindOf(.malformed("")) }),
            malformedArguments.count > 0 {
            throw ArgumentsError.invalidQuery("malformed query: \(malformedArguments)")
        }
        if case let standAloneInstructions = query.filter({ $0.isStandAloneInstruction }),
            !standAloneInstructions.isEmpty,
            query.count > 1 {
                throw ArgumentsError.invalidQuery("Can't have more than one argument with kind of instruction like \(standAloneInstructions)")
        }
        if case let temporalModifiers = query.filter({ $0.isTemporalConstraint }),
            temporalModifiers.count > 1 {
            throw ArgumentsError.invalidQuery("can't have multiple temporal modifier at same time (\(temporalModifiers)")
        }
    }

    // MARK: Private
    private func checkIgnoredArguments(from arguments: [ArgumentType]) -> [ArgumentType]? {
        return nil
    }
}

enum ArgumentsError: Error {
    case unknownArguments([ArgumentType])
    case invalidQuery(String)
    case emptyQuery
    case unknown
}

final class TerminalIO {
    enum IOType {
        case standard
        case error
    }

    func writeMessage(_ message: String, type: IOType = .standard) {
        switch type {
        case .standard:
            print(message)
        case .error:
            print("command failed: \(message)")
        }
    }
}

final class Koedo {
    // MARK: Properties
    private var parser: CommandLineArgumentsParser
    private var terminalIO: TerminalIO
    private lazy var menuFetcher: KoedoMenuFetcher = {
        return KoedoMenuFetcher()
    }()

    // MARK: Lifecycle
    init() {
        terminalIO = TerminalIO()
        parser = CommandLineArgumentsParser(with: [String](CommandLine.arguments.dropFirst()))
        do {
            try executeCommand()
        } catch let error {
            handleError(error)
        }
    }

    // MARK: Private
    private func executeCommand() throws {
        try parser.validateQuery()
        handleQuery()
    }

    private func handleQuery() {
        if let query = parser.query.first,
            parser.query.count == 1 {
                handleSingleQuery(query)
        } else {
            // Multiple meals
            handleMultipleQueries()
        }
    }

    private func handleSingleQuery(_ query: ArgumentType) {
        switch query {
        case .help:
            terminalIO.writeMessage(ArgumentType.usage)
        case .order:
            NSWorkspace.shared.open(URL(string: "https://koedo.fr/index.php/commande/")!)
        case .day(let weekDay):
            do {
                let menu = try menuFetcher.fetchMenu()
                terminalIO.writeMessage(menu.menu(forDay: weekDay))
            } catch {
                terminalIO.writeMessage(error.localizedDescription, type: .error)
            }
        case .week:
            do {
                let menu = try menuFetcher.fetchMenu()
                terminalIO.writeMessage(menu.menu(forDay: .monday))
                terminalIO.writeMessage(menu.menu(forDay: .tuesday))
                terminalIO.writeMessage(menu.menu(forDay: .wednesday))
                terminalIO.writeMessage(menu.menu(forDay: .thursday))
                terminalIO.writeMessage(menu.menu(forDay: .friday))
            } catch {
                terminalIO.writeMessage(error.localizedDescription, type: .error)
            }
        case .meal(let mealName):
            searchMeal(mealName)
        default:
            terminalIO.writeMessage("Unable to handle \(query) query. Please report.", type: .error)
        }
    }

    private func handleMultipleQueries() {
        let mealQueries = parser.query.filter({ $0.isKindOf(.meal("")) })
        if parser.query.count > mealQueries.count + 1 {
            terminalIO.writeMessage("One or more argument(s) from your query won't be taken in account due to an error. Please report", type: .error)
        }
        mealQueries.forEach {
            handleSingleQuery($0)
        }
    }

    private func searchMeal(_ meal: String) {
        do {
            let menu = try menuFetcher.fetchMenu()
            let result = menu.searchMeal(meal, time: parser.temporalConstraint)
            guard result.count > 0 else {
                terminalIO.writeMessage("No \(meal) planned 😞")
                return
            }

            result.forEach {
                terminalIO.writeMessage("\($0.day): \($0.dishType)")
            }

        } catch {
            terminalIO.writeMessage(error.localizedDescription, type: .error)
        }
    }

    private func handleError(_ error: Error) {
        switch error {
        case ArgumentsError.unknownArguments(let invalidArguments):
            let reason: [String] = invalidArguments.compactMap {
                switch $0 {
                case .unknown(let str): return str
                default: return nil
                }
            }
            executionFailed(reason: "invalid query (unknown arguments \(reason.joined(separator: ", ")))")
        case ArgumentsError.emptyQuery:
            executionFailed(reason: "no query")
        case ArgumentsError.unknown:
            executionFailed(reason: "query failed for unknown reason")
        case ArgumentsError.invalidQuery(let message):
            executionFailed(reason: message)
        default:
            terminalIO.writeMessage("\(error.localizedDescription)", type: .error)
        }
    }

    private func executionFailed(reason: String) {
        terminalIO.writeMessage(reason, type: .error)
        terminalIO.writeMessage(ArgumentType.usage)
    }
}

_ = Koedo()

