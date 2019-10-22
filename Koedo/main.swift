//
//  main.swift
//  Koedo
//
//  Created by Renaud Cousin on 10/21/19.
//  Copyright © 2019 AbsolutRenal. All rights reserved.
//

import Foundation

enum KoedoError: Error {
    case invalidURL
    case invalidFormat
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

final class KoedoCurry: NSObject {
    static func searchMeal() -> [MealDay]? {
        do {
            let webPageSource = try fetchMenu()
            let menu = parseSources(webPageSource)
            return getMealDays(from: menu)
        } catch {
            print("Error: unable to get \(Constants.meal) day \(error)")
            return nil
        }
    }

    private static func fetchMenu() throws -> String {
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
                    sourceError = KoedoError.invalidFormat
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

    private static func parseSources(_ sources: String) -> KoedoMenu {
        let tags = removeUselessHtmlTags(from: sources)
        var menu = extractMenu(from: tags)
        validateMenuOrder(&menu)
        return processMenu(menu)
    }

    private static func removeUselessHtmlTags(from source: String) -> [String] {
        let processed = source.components(separatedBy: "<div")
        let filtered = processed.filter {
            isDayTag($0) || isDishTag($0)
        }
        return filtered
    }

    private static func isDayTag(_ tag: String) -> Bool {
        return tag.contains(Constants.daySearchTagRef)
    }

    private static func isDishTag(_ tag: String) -> Bool {
        return tag.contains(Constants.dishSearchTagRef)
    }

    private static func extractMenu(from tags: [String]) -> [HtmlTagType] {
        return tags.compactMap {
            if isDayTag($0) {
                return extractDayName(from: $0)
            } else if isDishTag($0) {
                return extractDishName(from: $0)
            }
            return nil
        }
    }

    private static func extractDayName(from tag: String) -> HtmlTagType? {
        guard let dayString = processTag(tag,
                                         withStartPattern: Constants.daySplitStartTagRef,
                                         endPattern: Constants.daySplitEndTagRef) else {
            return nil
        }
        return .day(dayString)
    }

    private static func extractDishName(from tag: String) -> HtmlTagType? {
        guard let dishString = processTag(tag,
                                          withStartPattern: Constants.dishSplitStartTagRef,
                                          endPattern: Constants.dishSplitEndTagRef) else {
            return nil
        }
        return .dish(dishString)
    }

    private static func processTag(_ tag: String, withStartPattern startattern: String, endPattern: String) -> String? {
        let arr = tag.components(separatedBy: startattern)
        guard arr.count == 2 else {
            return nil
        }
        let arr2 = arr[1].components(separatedBy: endPattern)
        return arr2.first
    }

    private static func validateMenuOrder(_ menu: inout [HtmlTagType]) {
        guard menu.first(where: { $0.isKindOf(.day("")) }) != nil else {
            return
        }
        while !menu[0].isKindOf(.day("")) {
            menu.removeFirst()
        }
    }

    private static func processMenu(_ menu: [HtmlTagType]) -> KoedoMenu {
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

    private static func getMealDays(from menu: KoedoMenu) -> [MealDay] {
        var curryDays = [MealDay]()
        menu.forEach { key, value in
            let curryDishes = value.filter({ dish in
                return dish.lowercased().contains(Constants.meal)
            })
            curryDays.append(contentsOf: curryDishes.map { MealDay(day: key.rawValue, dishType: $0) })
        }
        return curryDays
    }
}

func main() {
    guard let mealDays = KoedoCurry.searchMeal(),
        mealDays.count > 0 else {
            print("No \(Constants.meal) planned this week 😞")
            return
    }
    mealDays.forEach {
        print("\($0.dishType) planned on \($0.day) 🤤")
    }
}

main()
