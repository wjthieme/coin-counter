//
//  ViewController.swift
//  CoinCounter
//
//  Created by Wilhelm Thieme on 11/08/2019.
//  Copyright © 2019 Sogeti Nederland B.V. All rights reserved.
//

import UIKit
import AVFoundation
import Vision
import Zip

fileprivate let videoQueue =  DispatchQueue(label: "VideoBuffer")
fileprivate let analyzeQueue = DispatchQueue(label: "AnalyzeQueue")


class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    override var preferredStatusBarStyle: UIStatusBarStyle { return .lightContent }
    
    private let scannerSquare = UIView()
    private var moneyView: MoneyView?
    
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var isCapturesSessionBuilt = false

    private var isPaused = false

    override func viewDidLoad() {
        super.viewDidLoad()
        
        scannerSquare.translatesAutoresizingMaskIntoConstraints = false
        scannerSquare.layer.borderColor = UIColor.blue.withAlphaComponent(0.5).cgColor
        scannerSquare.layer.borderWidth = 2
        scannerSquare.alpha = 0.8
        view.addSubview(scannerSquare)
        scannerSquare.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.5).activated()
        scannerSquare.heightAnchor.constraint(equalTo: scannerSquare.widthAnchor).activated()
        scannerSquare.centerXAnchor.constraint(equalTo: view.centerXAnchor).activated()
        scannerSquare.centerYAnchor.constraint(equalTo: view.centerYAnchor).activated()
    }
    
    
    private func buildCaptureSession() {
        defer { captureSession?.startRunning() }
        if isCapturesSessionBuilt { return }
        guard let captureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return }
        guard let input = try? AVCaptureDeviceInput(device: captureDevice) else { return }
        
        try? captureDevice.lockForConfiguration()
        
        captureDevice.focusMode = .autoFocus
        captureDevice.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
        
        captureSession = AVCaptureSession()
        captureSession?.sessionPreset = .photo
        captureSession?.addInput(input)
        
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession!)
        previewLayer?.videoGravity = .resizeAspectFill
        previewLayer?.frame = view.bounds
        view.layer.insertSublayer(previewLayer!, at: 0)
        
        let bufferOutput = AVCaptureVideoDataOutput()
        bufferOutput.setSampleBufferDelegate(self, queue: videoQueue)
        bufferOutput.alwaysDiscardsLateVideoFrames = true
        
        captureSession?.addOutput(bufferOutput)
        captureSession?.commitConfiguration()
        
        setFocalPoint()
        
        isCapturesSessionBuilt = true
    }
    
    private func setFocalPoint() {
        guard let input = self.captureSession?.inputs.first as? AVCaptureDeviceInput else { return }
        let device = input.device
        do { try device.lockForConfiguration() } catch { return }
        device.focusMode = .continuousAutoFocus
        device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
        device.unlockForConfiguration()
    }
    
    @objc private func shouldBuildCaptureSession() {
        AVCaptureDevice.requestAccess(for: .video) { response in
            DispatchQueue.main.async { response ? self.buildCaptureSession() : self.showAuthorizationAlert() }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        shouldBuildCaptureSession()
        NotificationCenter.default.addObserver(self, selector: #selector(shouldBuildCaptureSession), name: UIApplication.willEnterForegroundNotification, object: nil)
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        captureSession?.stopRunning()
        NotificationCenter.default.removeObserver(self)
    }
    
    private func showAuthorizationAlert() {
        let alert = UIAlertController(title: nil, message: NSLocalizedString("cameraAuthrorisationAlertMessage", comment: ""), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("settings", comment: ""), style: .default, handler: { _ in
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }))
        present(alert, animated: true, completion: nil)
    }
    
    private var xPercentage: CGFloat = 0
    private var yPercentage: CGFloat = 0
    private var screenAspect: CGFloat = 0
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        
        xPercentage = scannerSquare.frame.width / view.frame.width
        yPercentage = scannerSquare.frame.height / view.frame.height
        
        screenAspect = view.frame.width / view.frame.height

    }
    
    private func showMoney(_ money: Money) {
        guard Thread.isMainThread else { DispatchQueue.main.async { self.showMoney(money) }; return }
        moneyView = MoneyView(money)
        moneyView?.animateIn(with: view, animations: { self.scannerSquare.alpha = 0 })
        moneyView?.closeAnimations = { [weak self] in
            self?.scannerSquare.alpha = 0.8
        }
        moneyView?.closeAction = { [weak self] in
            self?.isPaused = false
            self?.labelHistory = []
        }
        moneyView?.shakeAction = { [weak self] in
            guard let self = self else { return }
            guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
            let context = CIContext()
            
            let images: [URL] = self.labelHistory.compactMap {
                let url = dir.appendingPathComponent("\(UUID().uuidString).jpg")
                do { try context.writeJPEGRepresentation(of: $0.0, to: url, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, options: [:]) } catch { print(error); return nil }
                return url
            }
            guard !images.isEmpty else { return }
            
            guard let url = try? Zip.quickZipFiles(images, fileName: NSLocalizedString("imagesZipFile", comment: "")) else { return }
            let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            self.present(share, animated: true, completion: nil)
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        analyzeQueue.async {
            if self.isPaused { return }
            var ci = CIImage(cvImageBuffer: buffer).oriented(.right)
            ci = self.cropImage(ci)
            self.labelHistory.append((ci, self.analyze(ci)))
            while self.labelHistory.count > self.maxHistory { self.labelHistory.removeFirst() }
            var counts = [String: Int]()
            self.labelHistory.forEach { if let id = $0.1 { counts[id] = (counts[id] ?? 0) + 1 } }
            guard let (value, count) = counts.max(by: {$0.1 < $1.1}) else { return }
            guard count > 2 else { return }
            guard let money = Money(value) else { return }
            self.isPaused = true
            self.showMoney(money)
        }
    }
    
    private var labelHistory: [(CIImage, String?)] = []
    private let maxHistory = 3
    
    private func analyze(_ ci: CIImage) -> String? {
        guard let vn = try? VNCoreMLModel(for: CoinClassifierV5().model) else { return nil }
        let request = VNCoreMLRequest(model: vn)
        
        let requestHandler = VNImageRequestHandler(ciImage: ci, options: [:])
        try? requestHandler.perform([request])
        
        guard let results = request.results as? [VNClassificationObservation] else { return nil }
        guard let first = results.first else { return nil }
        guard first.confidence > 0.5 else { return nil }

        return first.identifier
    }
    
    
    func cropImage(_ image: CIImage) -> CIImage {
        let imageAspect = image.extent.width / image.extent.height
        
        let width = screenAspect > imageAspect ? image.extent.width * xPercentage : image.extent.height * yPercentage
        let height = width
        
        let x = image.extent.width * 0.5 - width * 0.5
        let y = image.extent.height * 0.5 - height * 0.5
        
        let rect = CGRect(x: x, y: y, width: width, height: height)
        
        return image.cropped(to: rect)
    }

}

