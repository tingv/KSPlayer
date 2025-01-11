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
    convenience init?<U>(title: String, current: U?, list: [U], addDisabled: Bool = false, titleFunc: (U) -> String, completition: @escaping (String, U?) -> Void) {
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
            actions.insert(UIAction(title: "Disabled") { item in
                completition(item.title, nil)
            }, at: 0)
        }

        self.init(title: title, children: actions)
    }
}

#if !os(tvOS)
enum KSMenuType {
    case quality        // 资源版本
    case rate          // 播放速度
    case video         // 视频
    case audio         // 音轨
    case subtitle      // 字幕
    case setting       // 设置

    var image: UIImage? {
        switch self {
        case .quality:
            return UIImage(systemName: "list.and.film")
        case .rate:
            return UIImage(systemName: "circle.dashed")
        case .video:
            return UIImage(systemName: "video")
        case .audio:
            return UIImage(systemName: "speaker.wave.2")
        case .subtitle:
            return UIImage(systemName: "captions.bubble")
        case .setting:
            return UIImage(systemName: "gearshape.fill")
        }
    }
}

struct KSMenuGroup<U> {
    let type: KSMenuType
    let title: String
    let current: U?
    let list: [U]
    let addDisabled: Bool
}

extension UIButton {
    @available(iOS 14.0, *)
    func setMenu<U>(title: String, current: U?, list: [U], addDisabled: Bool = false, titleFunc: (U) -> String, completition handler: @escaping (U?) -> Void) {
        menu = UIMenu(title: title, current: current, list: list, addDisabled: addDisabled, titleFunc: titleFunc) { [weak self] title, value in
            guard let self else { return }
            handler(value)
            self.menu = self.menu?.updateActionState(actionTitle: title)
        }
    }

    @available(iOS 14.0, *)
    func setMenuWithSubmenu<U>(
        title: String,
        submenuGroups: [KSMenuGroup<U>],
        titleFunc: (U) -> String,
        settingHandler: (() -> Void)? = nil,
        completition handler: @escaping (KSMenuType, U?) -> Void
    ) {
        let submenus = submenuGroups.compactMap { group -> UIMenuElement? in
            if group.type == .setting {
                return UIAction(
                    title: group.title,
                    image: group.type.image
                ) { _ in
                    settingHandler?()
                }
            }

            return UIMenu(
                title: group.title,
                current: group.current,
                list: group.list,
                addDisabled: group.addDisabled,
                titleFunc: titleFunc
            ) { [weak self] title, value in
                handler(group.type, value)
                // 更新选中状态
                if let submenu = self?.menu?.children.first(where: { $0.title == group.title }) as? UIMenu {
                    self?.menu = UIMenu(
                        title: self?.menu?.title ?? "",
                        children: self?.menu?.children.map { menuItem in
                            if menuItem.title == group.title {
                                return UIMenu(
                                    title: submenu.title,
                                    image: group.type.image,
                                    children: submenu.children.map { action in
                                        if let action = action as? UIAction {
                                            action.state = action.title == title ? .on : .off
                                        }
                                        return action
                                    }
                                )
                            }
                            return menuItem
                        } ?? []
                    )
                }
            }
        }

        let menuItems = submenus.reversed().map { element -> UIMenuElement in
            if let action = element as? UIAction {
                return action
            }

            let submenu = element as! UIMenu
            let type = submenuGroups.first { $0.title == submenu.title }?.type
            return UIMenu(
                title: submenu.title,
                image: type?.image,
                children: submenu.children
            )
        }

        menu = UIMenu(title: title, children: menuItems)
    }
}
#endif

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
