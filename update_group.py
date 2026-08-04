import re

with open("iOS/Fidelity/Sources/Views/BespokeGroupDetailView.swift", "r") as f:
    content = f.read()

# Replace the first line of the history card (date) with the title
# And move date next to the item count
history_card = """            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(split.title)
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    HStack(spacing: 8) {
                        Text(formatter.string(from: split.date))
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                        Text("•")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.5))
                        Text("\\(split.items.count) items")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))"""
content = re.sub(r'            HStack \{\n                VStack\(alignment: \.leading, spacing: 4\) \{\n                    Text\(formatter\.string\(from: split\.date\)\)\n                        \.font\(\.headline\)\n                        \.foregroundColor\(\.white\)\n                    \n                    HStack\(spacing: 8\) \{\n                        Text\("\\\(split\.items\.count\) items"\)\n                            \.font\(\.subheadline\)\n                            \.foregroundColor\(\.white\.opacity\(0\.7\)\)', history_card, content)


with open("iOS/Fidelity/Sources/Views/BespokeGroupDetailView.swift", "w") as f:
    f.write(content)
