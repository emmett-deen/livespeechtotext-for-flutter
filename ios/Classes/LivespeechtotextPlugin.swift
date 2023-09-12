import Flutter
import UIKit
import Speech

public class LivespeechtotextPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
    private var recognitionTask: SFSpeechRecognitionTask?
    private var authorized: Bool = false
    private var recognizedText: String = ""
    public static let channelName: String = "livespeechtotext"
    public static let eventSuccess: String = "success"
    private var eventSink: FlutterEventSink? = nil
    private var currentLocale: Locale = Locale.current
    
  public static func register(with registrar: FlutterPluginRegistrar) {
      let channel = FlutterMethodChannel(name: self.channelName, binaryMessenger: registrar.messenger())
      let eventChannel = FlutterEventChannel(name: "\(self.channelName)/\(self.eventSuccess)", binaryMessenger: registrar.messenger())
      
      let instance = LivespeechtotextPlugin()
    
      eventChannel.setStreamHandler(instance)
      
      registrar.addMethodCallDelegate(instance, channel: channel)
  }
    
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "start":
        self.getPermissions{
            do {
                guard self.authorized else {
                    result("")
                    return
                }
                
                try self.start(flutterResult: result)
            } catch {
                result("")
            }
        }
        break
    case "stop":
        self.stop()
        result("")
        break
    case "getText":
        result(recognizedText)
        break
    case "getSupportedLocales":
        result(getSupportedLocales())
        break
    case "getLocaleDisplayName":
        result(getLocaleDisplayName())
        break
    case "setLocale":
        if let args = call.arguments as? Dictionary<String, Any>,
           let identifier = args["tag"] as? String {
            setLocale(localIdentifier: identifier)
         } else {
           
         }

        result("")
        break
    default:
        result(FlutterMethodNotImplemented)
    }
  }
    
    public func start(flutterResult: @escaping FlutterResult) throws {
        recognitionTask?.cancel()
        self.recognitionTask = nil
        
        if speechRecognizer?.locale.identifier != currentLocale.identifier {
            speechRecognizer = SFSpeechRecognizer(locale: currentLocale)
        }

        let audioSession = AVAudioSession.sharedInstance()
        // try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setCategory(.playAndRecord, mode: .default, options: .defaultToSpeaker)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer: AVAudioPCMBuffer, when: AVAudioTime) in
            self.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            fatalError("Unable to create a SFSpeechAudioBufferRecognitionRequest object")
        }
        
        recognitionRequest.shouldReportPartialResults = true

        if #available(iOS 13, *) {
            if speechRecognizer?.supportsOnDeviceRecognition ?? false{
                recognitionRequest.requiresOnDeviceRecognition = true
            }
        }

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { result, error in
            if let result = result {
                DispatchQueue.main.async {
                    let transcribedString = result.bestTranscription.formattedString
                    
                    self.eventSink?(transcribedString)
                    
                    flutterResult((transcribedString))
                }
            }
            if error != nil {
                self.stop()
                self.eventSink?(nil)
                flutterResult(nil)
                print(error)
            }
        }
    }
    
    public func stop() {
        self.audioEngine.stop()
        self.audioEngine.inputNode.removeTap(onBus: 0)
        self.recognitionRequest = nil
        self.recognitionTask?.cancel()
        self.recognitionTask = nil
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch{
            print("Warning: Unable to release audio session")
        }
    }
    
    public func getPermissions(callback: @escaping () -> Void){
        SFSpeechRecognizer.requestAuthorization{authStatus in
            OperationQueue.main.addOperation {
               switch authStatus {
                    case .authorized:
                        self.authorized = true
                        callback()
                        break
                    default:
                        break
               }
            }
        }
    }
    
    public func getSupportedLocales() -> [String: String] {
        var locales = [String: String]()
        let supportedLocales = SFSpeechRecognizer.supportedLocales()
        for locale in supportedLocales {
            let localizedName = locale.localizedString(forLanguageCode: locale.languageCode!)
            locales[locale.identifier] = localizedName
        }
        return locales
    }
    
    public func setLocale(localIdentifier: String) -> Void {
        stop()
        
        currentLocale = Locale(identifier: localIdentifier)
    }
    
    public func getLocaleDisplayName() -> String? {
        return currentLocale.localizedString(forLanguageCode: currentLocale.languageCode!)
    }
}
