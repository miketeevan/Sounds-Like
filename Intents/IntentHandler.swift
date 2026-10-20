import Intents

final class IntentHandler: INExtension, INPlayMediaIntentHandling {
    override func handler(for intent: INIntent) -> Any? { intent is INPlayMediaIntent ? self : nil }
    func resolveMediaItems(for intent: INPlayMediaIntent, with completion: @escaping ([INPlayMediaMediaItemResolutionResult]) -> Void) {
        if let station = Station.resolve(intent) { completion([.success(with: station.item)]) }
        else { completion([.unsupported()]) }
    }
    func handle(intent: INPlayMediaIntent, completion: @escaping (INPlayMediaIntentResponse) -> Void) {
        completion(INPlayMediaIntentResponse(code: Station.resolve(intent) != nil ? .handleInApp : .failure, userActivity: nil))
    }
}
