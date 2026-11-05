import Foundation
import TasksCore

@main
struct TasksMCPMain {
    static func main() {
        let handler = MCPServerHandler()
        while let line = readLine(strippingNewline: true) {
            if let response = handler.handleLine(line) {
                FileHandle.standardOutput.write(Data((response + "\n").utf8))
            }
        }
    }
}
