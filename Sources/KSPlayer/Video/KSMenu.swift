//
//  KSMenu.swift
//  KSPlayer
//
//  Created by Alanko5 on 15/12/2022.
//

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

// 定义菜单配置的基础协议
protocol MenuConfigurable {
    associatedtype ValueType
    var title: String { get }
    var current: ValueType? { get }
    var items: [ValueType] { get }
    var titleFunc: (ValueType) -> String { get }
    var handler: (ValueType?) -> Void { get }
    var addDisabled: Bool { get }
}

// 基础菜单配置结构
struct MenuConfig<T>: MenuConfigurable {
    typealias ValueType = T

    let title: String
    let current: T?
    let items: [T]
    let titleFunc: (T) -> String
    let handler: (T?) -> Void
    let addDisabled: Bool
}

// 类型擦除包装器，用于处理不同类型的菜单配置
struct AnyMenuConfig {
    private let _createMenu: () -> UIMenu?
    let title: String

    init<T>(_ config: MenuConfig<T>) {
        self.title = config.title
        self._createMenu = { UIMenu.create(from: config) }
    }

    func createMenu() -> UIMenu? {
        _createMenu()
    }
}

// 嵌套菜单结构
struct NestedMenu {
    let title: String
    let submenus: [AnyMenuConfig]

    init(title: String, submenus: [AnyMenuConfig]) {
        self.title = title
        self.submenus = submenus
    }

    // 便利构建方法
    static func build(
        title: String,
        @MenuBuilder _ builder: () -> [AnyMenuConfig]
    ) -> NestedMenu {
        NestedMenu(title: title, submenus: builder())
    }
}

extension UIMenu {
    func updateActionState(actionTitle: String? = nil) -> UIMenu {
        for action in children {
            guard let action = action as? UIAction else {
                continue
            }
            action.state = action.title == actionTitle ? .on : .off
        }
        return self
    }

    @available(tvOS 15.0, *)
    convenience init?<U>(
        title: String,
        current: U?,
        list: [U],
        addDisabled: Bool = false,
        titleFunc: (U) -> String,
        completition: @escaping (String, U?) -> Void
    ) {
        if list.count < (addDisabled ? 1 : 2) {
            return nil
        }

        var actions = list.map { value in
            let item = UIAction(title: titleFunc(value)) { item in
                completition(item.title, value)
            }

            if let current, titleFunc(value) == titleFunc(current) {
                item.state = .on
            }
            return item
        }

        if addDisabled {
            actions.insert(
                UIAction(title: NSLocalizedString("Disabled", comment: "")) { item in
                    completition(item.title, nil)
                },
                at: 0
            )
        }

        self.init(title: title, children: actions)
    }

    // 泛型方法：从任何符合 MenuConfigurable 协议的配置创建菜单
    static func create<Config: MenuConfigurable>(from config: Config) -> UIMenu? {
        guard config.items.count >= (config.addDisabled ? 1 : 2) else {
            return nil
        }

        var actions = config.items.reversed().map { value in
            let item = UIAction(title: config.titleFunc(value)) { action in
                config.handler(value)
            }

            if let current = config.current,
               config.titleFunc(current) == config.titleFunc(value) {
                item.state = .on
            }
            return item
        }

        if config.addDisabled {
            actions.insert(
                UIAction(title: "Disabled") { _ in
                    config.handler(nil)
                },
                at: 0
            )
        }

        return UIMenu(title: config.title, children: actions)
    }
}

#if !os(tvOS)

extension UIButton {
    @available(iOS 14.0, *)
    func setMenu<U>(
        title: String,
        current: U?,
        list: [U],
        addDisabled: Bool = false,
        titleFunc: (U) -> String,
        completition handler: @escaping (U?) -> Void
    ) {
        menu = UIMenu(
            title: title,
            current: current,
            list: list,
            addDisabled: addDisabled,
            titleFunc: titleFunc
        ) { [weak self] title, value in
            guard let self else { return }
            handler(value)
            self.menu = self.menu?.updateActionState(actionTitle: title)
        }
    }

    @available(iOS 14.0, *)
    func setNestedMenu(_ nestedMenu: NestedMenu) {
        let menuItems = nestedMenu.submenus.reversed().compactMap { $0.createMenu() }
        menu = UIMenu(title: nestedMenu.title, children: menuItems)
    }

    @available(iOS 14.0, *)
    func updateSubMenuState<T>(
        subMenuTitle: String,
        selectedItem: T,
        titleFunc: (T) -> String
    ) {
        guard let currentMenu = menu else { return }

        let updatedMenuItems = currentMenu.children.map { item -> UIMenuElement in
            guard let submenu = item as? UIMenu,
                  submenu.title == subMenuTitle else {
                return item
            }
            return submenu.updateActionState(actionTitle: titleFunc(selectedItem))
        }

        menu = UIMenu(title: currentMenu.title, children: updatedMenuItems)
    }
}

#endif

// 菜单构建器，提供声明式语法
@resultBuilder
struct MenuBuilder {
    static func buildBlock(_ components: AnyMenuConfig...) -> [AnyMenuConfig] {
        components
    }
}

// 便利扩展：为常见类型提供快捷创建方法
extension MenuConfig {
    static func create(
        title: String,
        current: T?,
        items: [T],
        titleFunc: @escaping (T) -> String = { "\($0)" },
        addDisabled: Bool = false,
        handler: @escaping (T?) -> Void
    ) -> MenuConfig<T> {
        MenuConfig(
            title: title,
            current: current,
            items: items,
            titleFunc: titleFunc,
            handler: handler,
            addDisabled: addDisabled
        )
    }
}

#if canImport(UIKit)

#else
public typealias UIMenu = NSMenu

public final class UIAction: NSMenuItem {
    private let handler: (UIAction) -> Void

    init(title: String, handler: @escaping (UIAction) -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(menuPressed), keyEquivalent: "")
        state = .off
        target = self
    }

    @objc private func menuPressed() {
        handler(self)
    }

    @available(*, unavailable)
    required init(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension UIMenu {
    var children: [NSMenuItem] {
        items
    }

    convenience init(title: String, children: [UIAction]) {
        self.init(title: title)
        for item in children {
            addItem(item)
        }
    }
}
#endif
