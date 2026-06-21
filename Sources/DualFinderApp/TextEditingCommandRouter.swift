import AppKit

@MainActor
enum TextEditingCommandRouter {
    static func perform(_ selector: Selector, in window: NSWindow? = NSApp.keyWindow) -> Bool {
        guard let textView = focusedTextView(in: window),
              textView.responds(to: selector)
        else {
            return false
        }

        return NSApp.sendAction(selector, to: textView, from: nil)
    }

    static func hasFocusedTextView(in window: NSWindow? = NSApp.keyWindow) -> Bool {
        focusedTextView(in: window) != nil
    }

    static func isTextResponder(_ responder: NSResponder?) -> Bool {
        responder is NSTextView
    }

    private static func focusedTextView(in window: NSWindow?) -> NSTextView? {
        guard isTextResponder(window?.firstResponder),
              let textView = window?.firstResponder as? NSTextView
        else {
            return nil
        }

        return textView
    }
}
