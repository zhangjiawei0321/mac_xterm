import XCTest
@testable import MobaLike

final class MobaLikeCoreTests: XCTestCase {

    // MARK: - JSON 持久化（会话配置可保存/加载）

    func testSessionConfigCodableRoundTrip() throws {
        let ssh = SessionConfig(name: "我的服务器", kind: .ssh, host: "192.168.1.10",
                                port: 2222, username: "root")
        let data = try JSONEncoder().encode(ssh)
        let back = try JSONDecoder().decode(SessionConfig.self, from: data)
        XCTAssertEqual(back.id, ssh.id)
        XCTAssertEqual(back, ssh)

        let serial = SessionConfig(name: "ECU", kind: .serial)
        let serialData = try JSONEncoder().encode(serial)
        let serialBack = try JSONDecoder().decode(SessionConfig.self, from: serialData)
        XCTAssertEqual(serialBack, serial)
    }

    func testSessionTreeCodableRoundTrip() throws {
        let tree: [TreeNode] = [
            .folder(SessionFolder(name: "服务器", children: [
                .session(SessionConfig(name: "A1", kind: .ssh, host: "10.0.0.1")),
                .folder(SessionFolder(name: "子目录", children: [
                    .session(SessionConfig(name: "B1", kind: .serial))
                ]))
            ])),
            .session(SessionConfig(name: "C1", kind: .ssh, host: "8.8.8.8"))
        ]
        let data = try JSONEncoder().encode(tree)
        let back = try JSONDecoder().decode([TreeNode].self, from: data)
        XCTAssertEqual(back, tree)

        // 结构导航
        XCTAssertEqual(back.count, 2)
        guard case .folder(let rootFolder) = back[0] else { return XCTFail("第一项应为文件夹") }
        XCTAssertEqual(rootFolder.name, "服务器")
        XCTAssertEqual(rootFolder.children.count, 2)
        guard case .folder(let inner) = rootFolder.children[1] else { return XCTFail("第二项应为文件夹") }
        XCTAssertEqual(inner.name, "子目录")
        guard case .session(let c1) = back[1] else { return XCTFail("第三条应为会话") }
        XCTAssertEqual(c1.host, "8.8.8.8")
    }

    // MARK: - 默认标签标题

    func testDefaultTabTitles() {
        XCTAssertEqual(SessionConfig(name: "", kind: .ssh).defaultTabTitle, "SSH")
        XCTAssertEqual(SessionConfig(name: "", kind: .ssh, host: "10.0.0.1", username: "admin").defaultTabTitle,
                       "admin@10.0.0.1")
        XCTAssertEqual(SessionConfig(name: "生产服务器", kind: .ssh, host: "x").defaultTabTitle, "生产服务器")

        var s = SessionConfig(name: "", kind: .serial)
        s.serial.device = "/dev/cu.usbserial-0001"
        XCTAssertEqual(s.defaultTabTitle, "/dev/cu.usbserial-0001")
    }

    // MARK: - 串口设备枚举（不崩溃、返回数组）

    func testSerialDeviceEnumeration() {
        let devices = SerialPort.listDevices()
        XCTAssertTrue(devices.allSatisfy { $0.hasPrefix("/dev/cu.") })
        // 不应包含标准包名之外的内容
        XCTAssertFalse(devices.contains { $0.contains(" ") })
    }

    // MARK: - Parity / FlowControl 序列化

    func testSerialOptionCodable() throws {
        let s = SerialSettings(device: "/dev/cu.x", baudRate: 9600, dataBits: 7,
                               parity: .even, stopBits: 2, flowControl: .hardware)
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(SerialSettings.self, from: data)
        XCTAssertEqual(back, s)
        XCTAssertEqual(back.parity, .even)
        XCTAssertEqual(back.flowControl, .hardware)
    }
}
