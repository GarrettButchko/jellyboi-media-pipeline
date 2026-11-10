import SwiftUI
import AppKit
import BaseColors
import LoggingKit

// MARK: - Flat Card Container Modifier (No Shadows)

public struct JellyCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 14

    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.sub)
            )
    }
}

public extension View {
    func jellyCard(cornerRadius: CGFloat = 14) -> some View {
        modifier(JellyCardModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - Progress Bar

public struct GlassProgressBar: View {
    let progress: Double
    var barHeight: CGFloat = 5
    var label: String? = nil
    var tintColor: Color = .accentColor

    public init(
        progress: Double,
        barHeight: CGFloat = 5,
        label: String? = nil,
        tintColor: Color = .accentColor
    ) {
        self.progress = progress
        self.barHeight = barHeight
        self.label = label
        self.tintColor = tintColor
    }

    public var body: some View {
        HStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.mainOpp.opacity(0.12))
                        .frame(height: barHeight)

                    Capsule()
                        .fill(tintColor)
                        .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(progress))), height: barHeight)
                        .animation(.smooth(duration: 0.35), value: progress)
                }
                .frame(height: barHeight, alignment: .center)
            }
            .frame(height: barHeight)

            if let label {
                Text(label)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.mainOpp.opacity(0.75))
                    .contentTransition(.numericText())
                    .animation(.smooth(duration: 0.25), value: label)
                    .fixedSize()
            }
        }
    }
}

// MARK: - Circular Icon Button

public struct JellyIconButton: View {
    let systemImage: String
    var size: CGFloat = 28
    var iconSize: CGFloat = 12
    var tintColor: Color = Color.mainOpp
    var action: () -> Void

    public init(
        systemImage: String,
        size: CGFloat = 28,
        iconSize: CGFloat = 12,
        tintColor: Color = Color.mainOpp,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.size = size
        self.iconSize = iconSize
        self.tintColor = tintColor
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(tintColor)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Circle())
    }
}

// MARK: - Empty State View

public struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var buttonTitle: String? = nil
    var secondaryButtonTitle: String? = nil
    var action: (() -> Void)? = nil
    var secondaryAction: (() -> Void)? = nil

    public init(
        icon: String,
        title: String,
        message: String,
        buttonTitle: String? = nil,
        secondaryButtonTitle: String? = nil,
        action: (() -> Void)? = nil,
        secondaryAction: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.buttonTitle = buttonTitle
        self.secondaryButtonTitle = secondaryButtonTitle
        self.action = action
        self.secondaryAction = secondaryAction
    }

    public var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 68, height: 68)

                Image(systemName: icon)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }

            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Color.mainOpp)
                .multilineTextAlignment(.center)

            Text(message)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(Color.mainOpp.opacity(0.6))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            if buttonTitle != nil || secondaryButtonTitle != nil {
                HStack(spacing: 10) {
                    if let buttonTitle, let action {
                        Button(action: action) {
                            Text(buttonTitle)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.tint(Color.accentColor).interactive(), in: Capsule())
                        .foregroundStyle(Color.white)
                    }

                    if let secondaryButtonTitle, let secondaryAction {
                        Button(action: secondaryAction) {
                            Text(secondaryButtonTitle)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: Capsule())
                        .foregroundStyle(Color.mainOpp)
                    }
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}
