import Foundation

public enum HUDLayout {
    public static let edgeMargin: CGFloat = 32

    public static func frame(
        panelSize: CGSize,
        in visibleFrame: CGRect,
        position: HUDPosition,
        edgeMargin: CGFloat = edgeMargin
    ) -> CGRect {
        let availableWidth = max(0, visibleFrame.width)
        let availableHeight = max(0, visibleFrame.height)
        let widthScale = panelSize.width > 0 ? availableWidth / panelSize.width : 1
        let heightScale = panelSize.height > 0 ? availableHeight / panelSize.height : 1
        let scale = max(0, min(1, min(widthScale, heightScale)))
        let fittedSize = CGSize(
            width: panelSize.width * scale,
            height: panelSize.height * scale
        )

        let preferredX: CGFloat
        switch position.horizontal {
        case .leading:
            preferredX = visibleFrame.minX + edgeMargin
        case .center:
            preferredX = visibleFrame.midX - fittedSize.width / 2
        case .trailing:
            preferredX = visibleFrame.maxX - edgeMargin - fittedSize.width
        }

        let preferredY: CGFloat
        switch position.vertical {
        case .top:
            preferredY = visibleFrame.maxY - edgeMargin - fittedSize.height
        case .center:
            preferredY = visibleFrame.midY - fittedSize.height / 2
        case .bottom:
            preferredY = visibleFrame.minY + edgeMargin
        }

        let maximumX = max(visibleFrame.minX, visibleFrame.maxX - fittedSize.width)
        let maximumY = max(visibleFrame.minY, visibleFrame.maxY - fittedSize.height)
        return CGRect(
            origin: CGPoint(
                x: min(max(preferredX, visibleFrame.minX), maximumX),
                y: min(max(preferredY, visibleFrame.minY), maximumY)
            ),
            size: fittedSize
        )
    }

    public static func screenIndices(
        for target: HUDDisplayTarget,
        screenFrames: [CGRect],
        mainScreenIndex: Int?,
        pointerLocation: CGPoint
    ) -> [Int] {
        guard !screenFrames.isEmpty else { return [] }
        let fallbackIndex = mainScreenIndex.flatMap {
            screenFrames.indices.contains($0) ? $0 : nil
        } ?? screenFrames.startIndex

        switch target {
        case .pointer:
            return [screenFrames.firstIndex { $0.contains(pointerLocation) } ?? fallbackIndex]
        case .main:
            return [fallbackIndex]
        case .all:
            return Array(screenFrames.indices)
        }
    }
}
