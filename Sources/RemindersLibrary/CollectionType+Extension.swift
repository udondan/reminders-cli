extension Collection where Index == Int {
    subscript(safe index: Int) -> Iterator.Element? {
        return index < self.count && index >= 0 ? self[index] : nil
    }
}
