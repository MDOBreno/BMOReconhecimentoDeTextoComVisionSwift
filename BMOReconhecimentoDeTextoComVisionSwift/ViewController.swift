//
//  ViewController.swift
//  BMOReconhecimentoDeTextoComVisionSwift
//
//  Created by Breno Medeiros on 08/07/20.
//  Copyright © 2020 ProgramasBMO. All rights reserved.
//

import UIKit
import AVFoundation
import Vision

class ViewController: UIViewController {
    
    // MARK: - Objetos da UI
    @IBOutlet weak var previewView: PreviewView!
    @IBOutlet weak var cutoutView: UIView!
    @IBOutlet weak var numberView: UILabel!
    var maskLayer = CAShapeLayer()
    // Orientação do dispositivo. Atualizado sempre que a orientação muda para uma
    // orientação suportada diferente.
    var currentOrientation = UIDeviceOrientation.portrait
    
    // MARK: - Capture Objetos Relacionados
    private let captureSession = AVCaptureSession()
    let captureSessionQueue = DispatchQueue(label: "com.example.apple-samplecode.CaptureSessionQueue")
    
    var captureDevice: AVCaptureDevice?
    
    var videoDataOutput = AVCaptureVideoDataOutput()
    let videoDataOutputQueue = DispatchQueue(label: "com.example.apple-samplecode.VideoDataOutputQueue")
    
    // MARK: - Região de interesse (ROI) e orientação do texto
    // Região do buffer de saída de dados de vídeo em que o reconhecimento deve ser executado.
    // É recalculado quando os limites da camada de visualização são conhecidos.
    var regionOfInterest = CGRect(x: 0, y: 0, width: 1, height: 1)
    // Orientação do texto a ser pesquisado na região de interesse.
    var textOrientation = CGImagePropertyOrientation.up
    
    // MARK: - Transformadas de coordenadas
    var bufferAspectRatio: Double!
    // Transforme da orientação da interface do usuário para a orientação do buffer.
    var uiRotationTransform = CGAffineTransform.identity
    // Transforme as coordenadas do canto inferior esquerdo para o canto superior esquerdo.
    var bottomToTopTransform = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -1)
    // Transforme coordenadas no ROI em coordenadas globais (ainda normalizadas).
    var roiToGlobalTransform = CGAffineTransform.identity
    
    // Vision -> Transformação de coordenadas AVF.
    var visionToAVFTransform = CGAffineTransform.identity
    
    // MARK: - Metodos da View controller
    
    @IBAction func handleTap(_ sender: UITapGestureRecognizer) {
        captureSessionQueue.async {
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
            }
            DispatchQueue.main.async {
                self.numberView.isHidden = true
            }
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Configurar a view de previsualizacao.
        previewView.session = captureSession
        
        // Configure a vista de recorte.
        cutoutView.backgroundColor = UIColor.gray.withAlphaComponent(0.5)
        maskLayer.backgroundColor = UIColor.clear.cgColor
        maskLayer.fillRule = .evenOdd
        cutoutView.layer.mask = maskLayer
        
        // Iniciar a sessão de captura é uma chamada de bloqueio. Realize a configuração usando
        // uma fila de despacho serial dedicada para impedir o bloqueio da thread main.
        captureSessionQueue.async {
            self.setupCamera()
            
            // Calcula a região de interesse agora que a câmera está configurada.
            DispatchQueue.main.async {
                // Descobrir o ROI(Regiao De Interesse) inicial.
                self.calculateRegionOfInterest()
            }
        }
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        // Apenas altere a orientação atual se a nova for paisagem ou
        // retrato. Você realmente não pode fazer nada sobre plano(flat) ou desconhecido(unknown).
        let deviceOrientation = UIDevice.current.orientation
        if deviceOrientation.isPortrait || deviceOrientation.isLandscape {
            currentOrientation = deviceOrientation
        }
        
        // Manipule a orientação do dispositivo na camada de visualização.
        if let videoPreviewLayerConnection = previewView.videoPreviewLayer.connection {
            if let newVideoOrientation = AVCaptureVideoOrientation(deviceOrientation: deviceOrientation) {
                videoPreviewLayerConnection.videoOrientation = newVideoOrientation
            }
        }
        
        // A orientação mudou: descubra uma nova Região De Interesse (ROI).
        calculateRegionOfInterest()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateCutout()
    }
    
    // MARK: - Configurar
    
    func calculateRegionOfInterest() {
        // Na orientação paisagem, o ROI desejado é especificado como a proporção de
        // largura do buffer em altura. Quando a interface do usuário for girada para o retrato, mantenha o
        // tamanho vertical igual (em pixels do buffer). Tente também manter o
        // tamanho horizontal o mesmo até uma proporção máxima.
        let desiredHeightRatio = 0.15
        let desiredWidthRatio = 0.6
        let maxPortraitWidth = 0.8
        
        // Descobrir o tamanho do ROI.
        let size: CGSize
        if currentOrientation.isPortrait || currentOrientation == .unknown {
            size = CGSize(width: min(desiredWidthRatio * bufferAspectRatio, maxPortraitWidth), height: desiredHeightRatio / bufferAspectRatio)
        } else {
            size = CGSize(width: desiredWidthRatio, height: desiredHeightRatio)
        }
        // Faça-o centrado.
        regionOfInterest.origin = CGPoint(x: (1 - size.width) / 2, y: (1 - size.height) / 2)
        regionOfInterest.size = size
        
        // ROI alterado, atualizando orientacao e transformada.
        setupOrientationAndTransform()
        
        // Atualize o recorte para corresponder ao novo ROI.
        DispatchQueue.main.async {
            // Aguarde o próximo ciclo de execução antes de atualizar o recorte. este
            // garante que a camada de visualização já tenha sua nova orientação.
            self.updateCutout()
        }
    }
    
    func updateCutout() {
        // Descobrir onde o recorte termina nas coordenadas da camada.
        let roiRectTransform = bottomToTopTransform.concatenating(uiRotationTransform)
        let cutout = previewView.videoPreviewLayer.layerRectConverted(fromMetadataOutputRect: regionOfInterest.applying(roiRectTransform))
        
        // Crie a máscara.
        let path = UIBezierPath(rect: cutoutView.frame)
        path.append(UIBezierPath(rect: cutout))
        maskLayer.path = path.cgPath
        
        // Mova a visualização numérica para baixo para abaixo do recorte.
        var numFrame = cutout
        numFrame.origin.y += numFrame.size.height
        numberView.frame = numFrame
    }
    
    func setupOrientationAndTransform() {
        // Recalcule a transformação afim entre as coordenadas do Vision e do AVF.
        
        // Compensar pela região de interesse.
        let roi = regionOfInterest
        roiToGlobalTransform = CGAffineTransform(translationX: roi.origin.x, y: roi.origin.y).scaledBy(x: roi.width, y: roi.height)
        
        // Compensar pela orientação (os buffers sempre vêm na mesma orientação).
        switch currentOrientation {
        case .landscapeLeft:
            textOrientation = CGImagePropertyOrientation.up
            uiRotationTransform = CGAffineTransform.identity
        case .landscapeRight:
            textOrientation = CGImagePropertyOrientation.down
            uiRotationTransform = CGAffineTransform(translationX: 1, y: 1).rotated(by: CGFloat.pi)
        case .portraitUpsideDown:
            textOrientation = CGImagePropertyOrientation.left
            uiRotationTransform = CGAffineTransform(translationX: 1, y: 0).rotated(by: CGFloat.pi / 2)
        default: // We default everything else to .portraitUp
            textOrientation = CGImagePropertyOrientation.right
            uiRotationTransform = CGAffineTransform(translationX: 0, y: 1).rotated(by: -CGFloat.pi / 2)
        }
        
        // Transformação ROI de visão completa para AVF.
        visionToAVFTransform = roiToGlobalTransform.concatenating(bottomToTopTransform).concatenating(uiRotationTransform)
    }
    
    func setupCamera() {
        guard let captureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: AVMediaType.video, position: .back) else {
            print("Could not create capture device.")
            return
        }
        self.captureDevice = captureDevice
        
        // NOTA:
        // Solicitar buffers de 4k permite o reconhecimento de texto menor, mas vai
        // consomir mais energia. Use o menor tamanho de buffer necessário para manter
        // uso baixo da bateria.
        if captureDevice.supportsSessionPreset(.hd4K3840x2160) {
            captureSession.sessionPreset = AVCaptureSession.Preset.hd4K3840x2160
            bufferAspectRatio = 3840.0 / 2160.0
        } else {
            captureSession.sessionPreset = AVCaptureSession.Preset.hd1920x1080
            bufferAspectRatio = 1920.0 / 1080.0
        }
        
        guard let deviceInput = try? AVCaptureDeviceInput(device: captureDevice) else {
            print("Could not create device input.")
            return
        }
        if captureSession.canAddInput(deviceInput) {
            captureSession.addInput(deviceInput)
        }
        
        // Configure a saída de dados de vídeo.
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        if captureSession.canAddOutput(videoDataOutput) {
            captureSession.addOutput(videoDataOutput)
            // NOTA:
            // Existe uma compensação a ser feita aqui. Ativar a estabilização vai
            // fornecer resultados temporariamente mais estáveis e deve ajudar o reconhecedor
            // a convergir. Mas se estiver ativado os buffers VideoDataOutput não vão
            // corresponder ao que é exibido na tela, o que torna o desenho do delimitador/fronteira de
            // caixas muito difíceis. Desative-o neste aplicativo para permitir exibicao do desenho detectando
            // caixas delimitadoras na tela.
            videoDataOutput.connection(with: AVMediaType.video)?.preferredVideoStabilizationMode = .off
        } else {
            print("Could not add VDO output")
            return
        }
        
        // Defina o zoom e o foco automático para ajudar a focar em textos muito pequenos.
        do {
            try captureDevice.lockForConfiguration()
            captureDevice.videoZoomFactor = 2
            captureDevice.autoFocusRangeRestriction = .near
            captureDevice.unlockForConfiguration()
        } catch {
            print("Could not set zoom level due to error: \(error)")
            return
        }
        
        captureSession.startRunning()
    }
    
    // MARK: - UI drawing and interaction
    
    func showString(string: String) {
        // Encontrou um número definido.
        // Pare a câmera de forma síncrona para garantir que não haja mais buffers
        // recebido. So entao atualize a exibição do número de forma assíncrona.
        captureSessionQueue.sync {
            self.captureSession.stopRunning()
            DispatchQueue.main.async {
                self.numberView.text = string
                self.numberView.isHidden = false
            }
        }
    }
}


// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Isso é implementado no VisionViewController.
    }
}

// MARK: - Utility extensions

extension AVCaptureVideoOrientation {
    init?(deviceOrientation: UIDeviceOrientation) {
        switch deviceOrientation {
        case .portrait: self = .portrait
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeLeft: self = .landscapeRight
        case .landscapeRight: self = .landscapeLeft
        default: return nil
        }
    }
}
