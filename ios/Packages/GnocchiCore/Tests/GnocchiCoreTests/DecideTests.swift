import Foundation
import Testing
@testable import GnocchiCore

struct DecideTests {
    @Test(arguments: [(2, ["e", "c"]), (4, ["e", "c", "a", "b"])])
    func candidatesMatchWeb(count: Int, expected: [String]) {
        let recipes = [
            DecideCandidate(id: "a", cookbookID: nil, tags: [], categories: [], folderID: nil),
            DecideCandidate(id: "b", cookbookID: nil, tags: [], categories: [], folderID: nil),
            DecideCandidate(id: "c", cookbookID: "book", tags: [], categories: [], folderID: nil),
            DecideCandidate(id: "d", cookbookID: nil, tags: ["kuchen"], categories: [], folderID: nil),
            DecideCandidate(id: "e", cookbookID: nil, tags: [], categories: [], folderID: nil)
        ]
        let history = ["a": "2026-11-12", "c": "2026-06-01"]
        let plan = [MealPlanEntry(id: "1", date: "2026-11-13", meal: .dinner, recipeID: "b")]
        #expect(DecideCandidates.pick(recipes, latest: history, plan: plan,
                                      today: "2026-11-14", seed: 42, count: count, folderID: nil) == expected)
    }

    // Aus advance(g, s, v, ["a","b","c","d"], 42, 0) in lib/decide.ts.
    @Test(arguments: [
        ("swipe", #"{"phase":"deck","deck":["a","b","c","d"],"deckNo":0,"seen":[],"score":{}}"#,
         #"[{"a":1,"b":2},{"a":2,"b":1}]"#, "b", #"{"phase":"fertig","reveal":{"kind":"match","fans":2}}"#),
        ("swipe", #"{"phase":"deck","deck":["a","b","c","d"],"deckNo":0,"seen":[],"score":{}}"#,
         #"[{"a":1},{"b":2}]"#, "", #"{"phase":"finale","options":["b","a","d"],"score":{"a":1,"b":2,"c":0,"d":0}}"#),
        ("swipe", #"{"phase":"finale","options":["a","b","c","d"],"score":{"a":2,"b":3,"c":4,"d":1}}"#,
         #"[{"strike":"c"},{"strike":"b"}]"#, "a", #"{"phase":"fertig","reveal":{"kind":"finale"}}"#),
        ("duell", #"{"phase":"sieb","options":["a","b","c","d"]}"#,
         #"[{"out":[]},{"out":[]}]"#, "", #"{"phase":"duell","pairs":[["d","a"],["c","b"]],"stage":0}"#),
        ("duell", #"{"phase":"duell","pairs":[["a","b"],["c","d"]],"stage":0}"#,
         #"[{"picks":["a","c"]},{"picks":["b","d"]}]"#, "", #"{"phase":"duell","pairs":[["a","d"]],"stage":1}"#),
        ("rad", #"{"phase":"lose","options":["a","b","c","d"]}"#,
         #"[{"tickets":{"b":3}},{"tickets":{"d":3}}]"#, "b", #"{"phase":"fertig","reveal":{"kind":"rad","options":["a","b","c","d"],"weights":[1,4,1,4]}}"#),
        ("loeffel", #"{"phase":"loeffel","options":["a","b","c","d"]}"#,
         #"[{"spoons":{"a":3,"b":2}},{"spoons":{"b":2,"c":3}}]"#, "b", #"{"phase":"fertig","reveal":{"kind":"loeffel","options":["a","b","c","d"],"totals":[3,4,3,0],"mins":[0,2,0,0]}}"#),
        ("jagd", #"{"phase":"jagd","options":["a","b","c","d"]}"#,
         #"[{"caught":{"a":3,"b":1}},{"caught":{"b":1,"c":3}}]"#, "b", #"{"phase":"fertig","reveal":{"kind":"jagd","options":["a","b","c","d"],"totals":[3,2,3,0],"mins":[0,1,0,0]}}"#),
        ("zug", #"{"phase":"zug","pairs":[["a","b"]],"stage":0}"#,
         #"[{"taps":[[140,1]]},{"taps":[[1,70]]}]"#, "a", #"{"phase":"fertig","reveal":{"kind":"zug","taps":142}}"#)
    ])
    func advancesLikeWeb(game: String, state: String, votes: String, winner: String, expected: String) throws {
        let decoder = JSONDecoder()
        let current = try decoder.decode(DecideState.self, from: Data(state.utf8))
        let submissions = try decoder.decode([DecideValue].self, from: Data(votes.utf8))
        let selectedGame = try #require(DecideGame(rawValue: game))
        let next = try #require(Decide.advance(game: selectedGame, state: current,
                                               submissions: submissions, candidates: ["a", "b", "c", "d"], seed: 42, round: 0))
        #expect(next.winner == (winner.isEmpty ? nil : winner))
        #expect(next.state == (try decoder.decode(DecideState.self, from: Data(expected.utf8))))
    }
}
