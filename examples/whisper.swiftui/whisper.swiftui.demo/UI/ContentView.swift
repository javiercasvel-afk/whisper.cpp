import SwiftUI
import Foundation
import AVFoundation
import UIKit
import Translation
import AppIntents

// ==========================================
// 1. INTERFAZ DE USUARIO DISCRETA
// ==========================================
struct ContentView: View {
    @StateObject private var manager = WhisperTranslationManager.shared
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea() // Fondo negro absoluto anti-miradas
            
            VStack(spacing: 20) {
                // Barra de estado minimalista superior
                HStack {
                    Circle()
                        .fill(manager.isRecording ? Color.red : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                    Text(manager.isRecording ? "SISTEMA SEGURO ACTIVO" : "BÚNKER LOCAL")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.gray)
                    Spacer()
                }
                .padding(.horizontal)
                
                // Zona 1: Transcripción del idioma original (Gris atenuado)
                ScrollView {
                    VStack(alignment: .leading) {
                        Text("ORIGINAL (INGLÉS / OTROS)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.blue.opacity(0.5))
                        Text(manager.englishText.isEmpty ? "..." : manager.englishText)
                            .font(.system(size: 16, design: .rounded))
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding()
                }
                
                Divider()
                    .background(Color.gray.opacity(0.15))
                
                // Zona 2: Visualización en Español (Texto principal en blanco)
                ScrollView {
                    VStack(alignment: .leading) {
                        Text("TRANSCRIPCIÓN / TRADUCCIÓN (ESPAÑOL)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.green.opacity(0.6))
                        Text(manager.spanishText.isEmpty ? "Esperando audio..." : manager.spanishText)
                            .font(.system(size: 16, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding()
                }
            }
            .padding(.top)
        }
    }
}

// ==========================================
// 2. EL MOTOR CENTRAL DE IA Y AUDIO
// ==========================================
@MainActor
class WhisperTranslationManager: ObservableObject {
    static let shared = WhisperTranslationManager()
    
    @Published var isRecording = false
    @Published var englishText = ""
    @Published var spanishText = ""
    
    private var textToSave = ""
    private var audioSession = AVAudioSession.sharedInstance()
    private var translator: Translation.Translator? // Espacio de nombres explícito
    
    init() {
        setupAudioSession()
        Task { await prepareTranslator() }
    }
    
    private func setupAudioSession() {
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: [.allowBluetooth])
        } catch {
            print("Error configurando el audio session: \(error)")
        }
    }
    
    private func prepareTranslator() async {
        do {
            // Forzamos la configuración explícita del SDK de traducción de iOS 18
            let configuration = Translation.Translator.Configuration(sourceLanguage: .english, targetLanguage: .spanish)
            self.translator = try await Translation.Translator(configuration: configuration)
        } catch {
            print("Error al inicializar el traductor nativo local: \(error)")
        }
    }
    
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        triggerHaptic(style: .medium)
        
        englishText = ""
        spanishText = ""
        textToSave = "--- Reunión del \(Date().formatted()) ---\n\n"
        
        print("Grabación e IA local iniciadas de forma silenciosa.")
    }
    
    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        
        triggerHaptic(style: .heavy)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.triggerHaptic(style: .heavy)
        }
        
        saveFinalTranscript()
    }
    
    func handleNewWhisperSegment(text: String, languageDetected: String) {
        guard isRecording else { return }
        
        if languageDetected == "es" {
            self.spanishText += " " + text
            self.textToSave += "[ES]: \(text)\n"
        } else {
            self.englishText += " " + text
            self.textToSave += "[EN]: \(text)\n"
            
            Task {
                if let translator = self.translator {
                    do {
                        let response = try await translator.translate(text)
                        self.spanishText += " " + response.targetText
                        self.textToSave += "[ES]: \(response.targetText)\n\n"
                    } catch {
                        print("Error en traducción local: \(error)")
                    }
                }
            }
        }
    }
    
    private func saveFinalTranscript() {
        let fileName = "Reunion_\(Date().fileSafeString()).txt"
        let fileManager = FileManager.default
        
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let fileURL = documentsDirectory.appendingPathComponent(fileName)
        
        do {
            try textToSave.write(to: fileURL, atomically: true, encoding: .utf8)
            print("Archivo guardado con éxito localmente en: \(fileURL.path)")
        } catch {
            print("Error al guardar el archivo: \(error)")
        }
    }
    
    private func triggerHaptic(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }
}

// ==========================================
// 3. ENLACE CON EL BOTÓN DE ACCIÓN FISICO
// ==========================================
struct ToggleRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Alternar Grabación Búnker"
    static var openAppWhenRun: Bool = false
    
    @MainActor
    func perform() async throws -> some IntentResult {
        WhisperTranslationManager.shared.toggleRecording()
        return .result()
    }
}

extension Date {
    func fileSafeString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: self)
    }
}
