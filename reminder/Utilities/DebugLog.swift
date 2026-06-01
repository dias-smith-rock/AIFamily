import Foundation

@inline(__always)
func print(
    _ items: Any...,
    separator: String = " ",
    terminator: String = "\n"
) {
#if DEBUG
    let rendered = items.map(String.init(describing:)).joined(separator: separator)
    Swift.print(rendered, terminator: terminator)
#endif
}
