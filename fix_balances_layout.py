import re

with open("iOS/Fidelity/Sources/Views/BespokeBalancesView.swift", "r") as f:
    content = f.read()

# I will find the end of the ScrollView and the end of the Memories section and swap them

old_structure = """                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        ForEach(memberBalances, id: \\.0) { member, total, breakdown in
                            balanceCard(member: member, total: total, breakdown: breakdown)
                        }
                    }
                    .padding(.horizontal, 30)
                    .padding(.bottom, 120)
                }
                // Memories Section"""
                
new_structure = """                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        ForEach(memberBalances, id: \\.0) { member, total, breakdown in
                            balanceCard(member: member, total: total, breakdown: breakdown)
                        }
                    }
                    .padding(.horizontal, 30)
                    .padding(.bottom, 40)
                    
                    Divider().background(Color.white.opacity(0.3)).padding(.horizontal, 30)
                    
                    // Memories Section"""

content = content.replace(old_structure, new_structure)

# Find the end of Memories Section
old_memories_end = """                        }
                        .padding(.horizontal, 30)
                    }
                }
                .padding(.top, 20)
                .padding(.bottom, 150) // Space for button
            }"""

new_memories_end = """                        }
                        .padding(.horizontal, 30)
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 150) // Space for button
                }
            }"""

content = content.replace(old_memories_end, new_memories_end)

with open("iOS/Fidelity/Sources/Views/BespokeBalancesView.swift", "w") as f:
    f.write(content)
