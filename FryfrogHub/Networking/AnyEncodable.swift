import Foundation

/// 类型擦除，用于把任意 Encodable 作为请求体传入
struct AnyEncodable: Encodable {
    let value: any Encodable

    init(_ value: some Encodable) {
        self.value = value
    }

    func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
    }
}
