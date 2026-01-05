import VitalinkCLI

@available(macOS 14.0, *)
func run() async {
    await Vitalink.main()
}

if #available(macOS 14.0, *) {
    await run()
} else {
    fatalError("Vitalink requires macOS 14.0 or later")
}
