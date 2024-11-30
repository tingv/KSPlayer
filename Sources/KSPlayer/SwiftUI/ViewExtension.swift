//
//  ViewExtension.swift
//  KSPlayer
//
//  Created by kintan on 11/30/24.
//

import SwiftUI

#if !os(tvOS)
@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
@MainActor
public struct PlayBackCommands: Commands {
    @FocusedObject
    private var config: KSVideoPlayer.Coordinator?
    public init() {}

    public var body: some Commands {
        CommandMenu("PlayBack") {
            if let config {
                Button(config.state.isPlaying ? "Pause" : "Resume") {
                    if config.state.isPlaying {
                        config.playerLayer?.pause()
                    } else {
                        config.playerLayer?.play()
                    }
                }
                .keyboardShortcut(.space, modifiers: .none)
                Button(config.isMuted ? "Mute" : "Unmute") {
                    config.isMuted.toggle()
                }
            }
        }
    }
}
#endif

@available(iOS 15, tvOS 16, macOS 12, *)
public struct MenuView<Label, SelectionValue, Content>: View where Label: View, SelectionValue: Hashable, Content: View {
    public let selection: Binding<SelectionValue>
    @ViewBuilder
    public let content: () -> Content
    @ViewBuilder
    public let label: () -> Label
    @State
    private var showMenu = false
    public var body: some View {
        if #available(tvOS 17, *) {
            Menu {
                Picker(selection: selection) {
                    content()
                } label: {
                    EmptyView()
                }
                .pickerStyle(.inline)
            } label: {
                label()
            }
            .menuIndicator(.hidden)
        } else {
            Picker(selection: selection, content: content, label: label)
            #if !os(macOS)
                .pickerStyle(.navigationLink)
            #endif
                .frame(height: 50)
            #if os(tvOS)
                .frame(width: 110)
            #endif
        }
    }
}

@available(iOS 16, tvOS 16, macOS 13, *)
public struct PlatformView<Content: View>: View {
    private let content: () -> Content
    public var body: some View {
        #if os(tvOS)
        // tvos需要加NavigationStack，不然无法出现下拉框。iOS不能加NavigationStack，不然会丢帧。
        NavigationStack {
            ScrollView {
                content()
                    .padding()
            }
        }
        .pickerStyle(.navigationLink)
        #else
        Form {
            content()
        }
        .formStyle(.grouped)
        #endif
    }

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }
}

extension EventModifiers {
    static let none = Self()
}

extension View {
    func then(_ body: (inout Self) -> Void) -> Self {
        var result = self
        body(&result)
        return result
    }
}

public extension View {
    /// Applies the given transform if the given condition evaluates to `true`.
    /// - Parameters:
    ///   - condition: The condition to evaluate.
    ///   - transform: The transform to apply to the source `View`.
    /// - Returns: Either the original `View` or the modified `View` if the condition is `true`.
    @ViewBuilder
    func `if`(_ condition: @autoclosure () -> Bool, transform: (Self) -> some View) -> some View {
        if condition() {
            transform(self)
        } else {
            self
        }
    }

    @ViewBuilder
    func `if`(_ condition: @autoclosure () -> Bool, if ifTransform: (Self) -> some View, else elseTransform: (Self) -> some View) -> some View {
        if condition() {
            ifTransform(self)
        } else {
            elseTransform(self)
        }
    }

    @ViewBuilder
    func ifLet<T: Any>(_ optionalValue: T?, transform: (Self, T) -> some View) -> some View {
        if let value = optionalValue {
            transform(self, value)
        } else {
            self
        }
    }
}

extension Bool {
    static var iOS16: Bool {
        guard #available(iOS 16, *) else {
            return true
        }
        return false
    }
}

extension View {
    func onKeyPressLeftArrow(action: @escaping () -> Void) -> some View {
        if #available(iOS 17.0, macOS 14.0, tvOS 17.0, *) {
            return onKeyPress(.leftArrow) {
                action()
                return .handled
            }
        } else {
            return self
        }
    }

    func onKeyPressRightArrow(action: @escaping () -> Void) -> some View {
        if #available(iOS 17.0, macOS 14.0, tvOS 17.0, *) {
            return onKeyPress(.rightArrow) {
                action()
                return .handled
            }
        } else {
            return self
        }
    }

    func onKeyPressSapce(action: @escaping () -> Void) -> some View {
        if #available(iOS 17.0, macOS 14.0, tvOS 17.0, *) {
            return onKeyPress(.space) {
                action()
                return .handled
            }
        } else {
            return self
        }
    }

    func allowedDynamicRange() -> some View {
        if #available(iOS 17.0, macOS 14.0, tvOS 17.0, *) {
            return self.allowedDynamicRange(KSOptions.subtitleDynamicRange)
        } else {
            return self
        }
    }

    #if !os(tvOS)
    func textSelection() -> some View {
        if #available(iOS 15.0, macOS 12.0, *) {
            return self.textSelection(.enabled)
        } else {
            return self
        }
    }
    #endif

    func italic(value: Bool) -> some View {
        if #available(iOS 16.0, macOS 13.0, tvOS 16.0, *) {
            return self.italic(value)
        } else {
            return self
        }
    }

    func ksIgnoresSafeArea() -> some View {
        if #available(iOS 14.0, macOS 11.0, tvOS 14.0, *) {
            return self.ignoresSafeArea()
        } else {
            return self
        }
    }
}
