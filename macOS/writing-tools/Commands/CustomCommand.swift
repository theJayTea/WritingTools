import Foundation

struct CustomCommand: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var prompt: String
    var icon: String
    var useResponseWindow: Bool
    
    init(id: UUID = UUID(), name: String, prompt: String, icon: String, useResponseWindow: Bool = false) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.icon = icon
        self.useResponseWindow = useResponseWindow
    }
}

class CustomCommandsManager: ObservableObject {
    @Published private(set) var commands: [CustomCommand] = []
    private let saveKey = "custom_commands"
    
    init() {
        loadCommands()
    }
    
    private func loadCommands() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode([CustomCommand].self, from: data) {
            commands = decoded
        }
    }
    
    private func saveCommands() {
        if let encoded = try? JSONEncoder().encode(commands) {
            UserDefaults.standard.set(encoded, forKey: saveKey)
        }
    }
    
    func addCommand(_ command: CustomCommand) {
        commands.append(command)
        saveCommands()
    }
    
    func updateCommand(_ command: CustomCommand) {
        if let index = commands.firstIndex(where: { $0.id == command.id }) {
            commands[index] = command
            saveCommands()
        }
    }
    
    func deleteCommand(_ command: CustomCommand) {
        commands.removeAll { $0.id == command.id }
        saveCommands()
    }
}
