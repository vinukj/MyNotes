import AppKit
import SwiftUI

struct SelectionCopyTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedText: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = SelectionCopyScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true

        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(containerSize: NSSize(width: 1, height: CGFloat.greatestFiniteMagnitude))
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        let textView = SelectionCopyTextView(frame: .zero, textContainer: textContainer)
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textContainer.widthTracksTextView = true
        textContainer.containerSize = NSSize(width: 1, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = .zero
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        scrollView.documentView = textView
        textView.string = text
        updateBindings(for: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? SelectionCopyTextView else { return }
        updateBindings(for: textView)
        if textView.string != text {
            textView.string = text
        }
    }

    private func updateBindings(for textView: SelectionCopyTextView) {
        let textBinding = $text
        let selectionBinding = $selectedText
        textView.onTextChange = { textBinding.wrappedValue = $0 }
        textView.onSelectionChange = { selectionBinding.wrappedValue = $0 }
    }
}

private final class SelectionCopyScrollView: NSScrollView {
    override func layout() {
        super.layout()
        guard let textView = documentView as? SelectionCopyTextView else { return }
        let viewportSize = contentView.bounds.size
        guard viewportSize.width > 0, viewportSize.height > 0 else { return }

        if textView.frame.width != viewportSize.width || textView.frame.height < viewportSize.height {
            textView.setFrameSize(NSSize(width: viewportSize.width, height: max(textView.frame.height, viewportSize.height)))
        }
    }
}

private final class SelectionCopyTextView: NSTextView, NSTextViewDelegate {
    var onTextChange: ((String) -> Void)?
    var onSelectionChange: ((String) -> Void)?

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        delegate = self
    }

    func textDidChange(_ notification: Notification) {
        onTextChange?(string)
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        let range = selectedRange()
        guard range.length > 0, NSMaxRange(range) <= (string as NSString).length else {
            onSelectionChange?("")
            return
        }

        onSelectionChange?((string as NSString).substring(with: range))
    }
}
