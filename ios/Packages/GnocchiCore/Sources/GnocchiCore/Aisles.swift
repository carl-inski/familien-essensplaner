// Regeln und Reihenfolge aus lib/aisles.ts.
public enum Aisles {
    private static let order = ["Obst & Gemüse","Kühlregal","Frischetheke","Trockenware","Gewürze","Tiefkühl","Getränke","Sonstiges"]
    private static let rules: [(String, [String])] = [
        ("Obst & Gemüse", ["salat","latich","frische ananas"]),
        ("Tiefkühl", ["(tk","tk-","tk ","tiefkühl"]),
        ("Trockenware", ["kokosmilch","passierte","tomatenmark","(dose","dose)",", dose","brühe","öl","essig","sojasauce","mirin","hot sauce","süß-sauer","milchreis","reispapier","erdnussbutter","marmelade","honig","sirup","schoko","pistazie","haselnuss","cashew","kerne","kapern","oliven"]),
        ("Gewürze", ["salz","pfeffer","pulver","zimt","kreuzkümmel","muskat","getrocknet","dill","sesam","currypaste","misopaste","chili","thymian","räucherpaprika"]),
        ("Frischetheke", ["hähnchen","huhn","schwein","rinderhack","hack","schinken","lachs","garnele","fisch","speck","geschnetzeltes","filet"]),
        ("Kühlregal", ["feta","käse","mozzarella","parmesan","cheddar","schmand","sahne","milch","joghurt","butter","frischkäse","crème","creme","eier","ei","mürbeteig","gnocchi","lasagneblätter","quark","guacamole","tortilla"]),
        ("Obst & Gemüse", ["zwiebel","knoblauch","ingwer","tomate","spinat","rucola","salat","latich","gurke","karotte","möhre","paprika","zitrone","limette","orange","banane","ananas","avocado","petersilie","koriander","minze","basilikum","schnittlauch","oregano","champignon","pilz","spargel","kartoffel","sprossen","lauch","zucchini","aubergine","beeren","apfel"]),
        ("Trockenware", ["nudel","pasta","penne","farfalle","reis","mehl","hefe","zucker","kichererbsen","bohnen","mais","senf","brot","chips","balsamico"]),
        ("Getränke", ["wein","sake","sherry"])
    ]

    public static func forIngredient(_ name: String) -> String {
        let full = name.lowercased()
        let bare = full.replacing(pattern: #"\(.*?\)"#, with: " ")
        return rules.first { _, words in
            words.contains { word in
                let target = word.contains("(") || word.contains(")") || word.contains("tk") ? full : bare
                if word.count > 2 { return target.contains(word) }
                return target.matches(pattern: "(^|[^\\p{L}])\(word)([^\\p{L}]|$)")
            }
        }?.0 ?? "Sonstiges"
    }

    public static func rank(_ aisle: String) -> Int {
        order.firstIndex(of: aisle) ?? order.count
    }
}
