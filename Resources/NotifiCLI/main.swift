import Foundation
import UserNotifications
import AppKit

// MARK: - Argument Parsing
var title: String?
var subtitle: String?
var message: String?
var actions: [String] = []
var imagePath: String?
var soundName: String?
var replyPlaceholder: String?
var openUrl: String?
var iconPath: String?

var args = CommandLine.arguments.dropFirst()
while let arg = args.popFirst() {
    switch arg {
    case "-title":
        title = args.popFirst()
    case "-subtitle":
        subtitle = args.popFirst()
    case "-message":
        message = args.popFirst()
    case "-actions":
        if let actionStr = args.popFirst() {
            actions = actionStr.split(separator: ",").map { String($0) }
        }
    case "-image":
        imagePath = args.popFirst()
    case "-sound":
        soundName = args.popFirst()
    case "-reply":
        replyPlaceholder = args.popFirst()
    case "-url":
        openUrl = args.popFirst()
    case "-icon":
        iconPath = args.popFirst()
    default:
        break
    }
}

guard let notificationTitle = title, let notificationMessage = message else {
    print("Usage: NotifiCLI -title \"Title\" -message \"Message\" [-subtitle \"Subtitle\"] [-actions \"Yes,No\"] [-reply \"Placeholder\"] [-url \"https://...\"] [-image \"/path/to/image.png\"] [-sound \"Name\"]")
    exit(1)
}

// MARK: - Notification
let center = UNUserNotificationCenter.current()

class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    var selectedAction: String?
    let semaphore = DispatchSemaphore(value: 0)
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        
        // Handle Text Input
        if let textResponse = response as? UNTextInputNotificationResponse {
            selectedAction = textResponse.userText
        } 
        // Handle Default Click (Open URL)
        else if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            selectedAction = "default"
            if let openUrl = openUrl, let url = URL(string: openUrl) {
                NSWorkspace.shared.open(url)
            }
        } else if response.actionIdentifier == UNNotificationDismissActionIdentifier {
            selectedAction = "dismissed"
        } else {
            selectedAction = response.actionIdentifier
        }
        
        completionHandler()
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        var options: UNNotificationPresentationOptions = [.banner]
        if notification.request.content.sound != nil {
            options.insert(.sound)
        }
        completionHandler(options)
    }
}

let delegate = NotificationDelegate()
center.delegate = delegate

// Request authorization
center.requestAuthorization(options: [.alert, .sound]) { granted, error in
    if let error = error {
        print("Error requesting auth: \(error.localizedDescription)")
    }
}

// Register action category if needed
var notificationActions: [UNNotificationAction] = []

if let replyPlaceholder = replyPlaceholder {
    let replyAction = UNTextInputNotificationAction(
        identifier: "REPLY_ACTION",
        title: "Reply",
        options: [.foreground],
        textInputButtonTitle: "Send",
        textInputPlaceholder: replyPlaceholder
    )
    notificationActions.append(replyAction)
}

if !actions.isEmpty {
    let customActions = actions.map { actionTitle in
        UNNotificationAction(identifier: actionTitle, title: actionTitle, options: [])
    }
    notificationActions.append(contentsOf: customActions)
}

if !notificationActions.isEmpty {
    let category = UNNotificationCategory(identifier: "ACTIONS_CATEGORY",
                                           actions: notificationActions,
                                           intentIdentifiers: [],
                                           options: [.customDismissAction])
    let categorySemaphore = DispatchSemaphore(value: 0)
    center.setNotificationCategories([category])
    center.getNotificationCategories { _ in
        categorySemaphore.signal()
    }
    _ = categorySemaphore.wait(timeout: .now() + 1.0)
}

// Create notification content
let content = UNMutableNotificationContent()
content.title = notificationTitle
if let notificationSubtitle = subtitle {
    content.subtitle = notificationSubtitle
}
content.body = notificationMessage

content.sound = nil

if !notificationActions.isEmpty {
    content.categoryIdentifier = "ACTIONS_CATEGORY"
}

// Handle remote image
if let path = imagePath, (path.lowercased().hasPrefix("http://") || path.lowercased().hasPrefix("https://")), let url = URL(string: path) {
    let tempDir = URL(fileURLWithPath: "/tmp/notificli")
    do {
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
        let fileName = url.lastPathComponent.isEmpty ? "image-\(UUID().uuidString)" : url.lastPathComponent
        let destinationURL = tempDir.appendingPathComponent(fileName)
        
        if let data = try? Data(contentsOf: url) {
            try data.write(to: destinationURL)
            imagePath = destinationURL.path
        }
    } catch {
        fputs("Warning: Failed to process remote image: \(error.localizedDescription)\n", stderr)
    }
}

// Add image attachment if specified
if let imagePath = imagePath {
    let imageURL = URL(fileURLWithPath: imagePath)
    if FileManager.default.fileExists(atPath: imagePath) {
        do {
            let tempAttachmentURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + imageURL.pathExtension)
            try FileManager.default.copyItem(at: imageURL, to: tempAttachmentURL)
            
            let attachment = try UNNotificationAttachment(identifier: "image", url: tempAttachmentURL, options: nil)
            content.attachments = [attachment]
        } catch {
            fputs("Warning: Could not attach image: \(error.localizedDescription)\n", stderr)
        }
    }
}

// Schedule notification
let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)

let notificationSemaphore = DispatchSemaphore(value: 0)

center.add(request) { error in
    if let error = error {
        print("Error scheduling notification: \(error.localizedDescription)")
        exit(1)
    }
    notificationSemaphore.signal()
}

_ = notificationSemaphore.wait(timeout: .now() + 2.0)

// Play sound after notification is scheduled
if let soundName = soundName {
    var soundPlayed = false
    
    if let resourcePath = Bundle.main.resourcePath {
        let soundPath = (resourcePath as NSString).appendingPathComponent(soundName)
        if FileManager.default.fileExists(atPath: soundPath) {
            if let sound = NSSound(contentsOfFile: soundPath, byReference: true) {
                sound.play()
                soundPlayed = true
            }
        }
    }
    
    if !soundPlayed {
        let nameWithoutExt = (soundName as NSString).deletingPathExtension
        if let sound = NSSound(named: NSSound.Name(nameWithoutExt)) {
            sound.play()
            soundPlayed = true
        }
    }
    
    if !soundPlayed && FileManager.default.fileExists(atPath: soundName) {
        if let sound = NSSound(contentsOfFile: soundName, byReference: true) {
            sound.play()
            soundPlayed = true
        }
    }
    
    if soundPlayed {
        Thread.sleep(forTimeInterval: 1.0)
    }
}

// Wait for user response if actions exist or reply is requested
if !actions.isEmpty || replyPlaceholder != nil || openUrl != nil {
    while delegate.selectedAction == nil {
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
    }
    
    if let action = delegate.selectedAction {
        print(action)
    }
}
