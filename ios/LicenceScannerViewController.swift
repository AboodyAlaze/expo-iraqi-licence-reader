import AVFoundation
import UIKit
import Vision

/// أي وجه من البطاقة نمسح
enum ScanSide {
  case front
  case back
}

/// كم إطار لازم يتفق على نفس القراءة قبل ما نقبلها
private let frontVotes = 3
private let backVotes = 2
private let fallbackAfterFrames = 40

/// شاشة كاميرا تقرأ وجه أو ظهر إجازة السياقة بـ Vision.
///
/// الوجه: نطلب اتفاق 3 إطارات على نفس الـ MRZ — رقم التحقق وحده
/// ممكن تصادفه قراءة خاطئة باحتمال 1 من 10.
///
/// الظهر: نمرّر إحداثيات كل سطر، فنستنتج صف كل زوج تواريخ هندسياً،
/// ونطلب اتفاق إطارين لأن الجدول ما عنده رقم تحقق.
final class LicenceScannerViewController: UIViewController {

  private let side: ScanSide
  private let onResult: (String?) -> Void

  private let session = AVCaptureSession()
  private let queue = DispatchQueue(label: "licence.scanner.queue")
  private var previewLayer: AVCaptureVideoPreviewLayer?

  private let hintLabel = UILabel()
  private let votesLabel = UILabel()
  private let fallbackButton = UIButton(type: .system)

  // الحالة التالية تُلمس فقط من `queue`
  private var finished = false
  private var frames = 0
  private var votes: [String: Int] = [:]
  private var bestFront: [String: LicenceFront] = [:]
  private var bestViz: LicenceFront?

  init(side: ScanSide, onResult: @escaping (String?) -> Void) {
    self.side = side
    self.onResult = onResult
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

  // MARK: دورة الحياة

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    setupCamera()
    setupOverlay()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    queue.async { [weak self] in
      guard let self = self, !self.session.isRunning else { return }
      self.session.startRunning()
    }
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    queue.async { [weak self] in
      guard let self = self, self.session.isRunning else { return }
      self.session.stopRunning()
    }
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    previewLayer?.frame = view.bounds
  }

  // MARK: الإعداد

  private func setupCamera() {
    session.sessionPreset = .hd1920x1080

    guard let device = AVCaptureDevice.default(for: .video),
          let input = try? AVCaptureDeviceInput(device: device),
          session.canAddInput(input) else {
      finish(json: nil)
      return
    }
    session.addInput(input)

    let output = AVCaptureVideoDataOutput()
    output.alwaysDiscardsLateVideoFrames = true
    output.setSampleBufferDelegate(self, queue: queue)
    guard session.canAddOutput(output) else {
      finish(json: nil)
      return
    }
    session.addOutput(output)

    let layer = AVCaptureVideoPreviewLayer(session: session)
    layer.videoGravity = .resizeAspectFill
    layer.frame = view.bounds
    view.layer.addSublayer(layer)
    previewLayer = layer
  }

  private func setupOverlay() {
    // الشريط السفلي
    let bottom = UIView()
    bottom.backgroundColor = UIColor.black.withAlphaComponent(0.65)
    bottom.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(bottom)

    hintLabel.text = side == .front
      ? "وجّه الكاميرا على وجه البطاقة"
      : "وجّه الكاميرا على جدول الفئات بالظهر"
    hintLabel.textColor = .white
    hintLabel.textAlignment = .center
    hintLabel.numberOfLines = 0
    hintLabel.font = .systemFont(ofSize: 15)

    let tips = UILabel()
    tips.text = "ضوء جيد · بدون ميلان · خلفية فاتحة"
    tips.textColor = UIColor.white.withAlphaComponent(0.7)
    tips.textAlignment = .center
    tips.font = .systemFont(ofSize: 12)

    let stack = UIStackView(arrangedSubviews: [hintLabel, tips])
    stack.axis = .vertical
    stack.spacing = 4
    stack.translatesAutoresizingMaskIntoConstraints = false
    bottom.addSubview(stack)

    // عدّاد التصويت
    votesLabel.textColor = .white
    votesLabel.font = .monospacedSystemFont(ofSize: 18, weight: .regular)
    votesLabel.textAlignment = .center
    votesLabel.backgroundColor = UIColor(red: 0.11, green: 0.37, blue: 0.13, alpha: 0.85)
    votesLabel.layer.cornerRadius = 16
    votesLabel.clipsToBounds = true
    votesLabel.isHidden = true
    votesLabel.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(votesLabel)

    // إلغاء
    let cancel = UIButton(type: .system)
    cancel.setTitle("إلغاء", for: .normal)
    cancel.setTitleColor(.white, for: .normal)
    cancel.backgroundColor = UIColor.black.withAlphaComponent(0.6)
    cancel.layer.cornerRadius = 8
    cancel.translatesAutoresizingMaskIntoConstraints = false
    cancel.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
    view.addSubview(cancel)

    // مخرج احتياطي للوجه
    fallbackButton.setTitle("اكتفِ بقراءة الوجه", for: .normal)
    fallbackButton.setTitleColor(.white, for: .normal)
    fallbackButton.backgroundColor = UIColor.black.withAlphaComponent(0.6)
    fallbackButton.layer.cornerRadius = 8
    fallbackButton.isHidden = true
    fallbackButton.translatesAutoresizingMaskIntoConstraints = false
    fallbackButton.addTarget(self, action: #selector(fallbackTapped), for: .touchUpInside)
    view.addSubview(fallbackButton)

    NSLayoutConstraint.activate([
      bottom.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      bottom.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      bottom.bottomAnchor.constraint(equalTo: view.bottomAnchor),

      stack.topAnchor.constraint(equalTo: bottom.topAnchor, constant: 16),
      stack.leadingAnchor.constraint(equalTo: bottom.leadingAnchor, constant: 16),
      stack.trailingAnchor.constraint(equalTo: bottom.trailingAnchor, constant: -16),
      stack.bottomAnchor.constraint(equalTo: bottom.safeAreaLayoutGuide.bottomAnchor, constant: -8),

      votesLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
      votesLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      votesLabel.widthAnchor.constraint(equalToConstant: 100),
      votesLabel.heightAnchor.constraint(equalToConstant: 36),

      cancel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
      cancel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      cancel.widthAnchor.constraint(equalToConstant: 90),
      cancel.heightAnchor.constraint(equalToConstant: 40),

      fallbackButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      fallbackButton.bottomAnchor.constraint(equalTo: bottom.topAnchor, constant: -16),
      fallbackButton.heightAnchor.constraint(equalToConstant: 40),
      fallbackButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 160),
    ])
  }

  // MARK: الأزرار

  @objc private func cancelTapped() {
    queue.async { [weak self] in self?.finish(json: nil) }
  }

  @objc private func fallbackTapped() {
    queue.async { [weak self] in
      guard let self = self, let v = self.bestViz else { return }
      self.finish(json: LicenceJson.front(v))
    }
  }

  // MARK: الإنهاء

  /// يُستدعى من `queue` — يضمن إن النتيجة ترجع مرة وحدة فقط
  private func finish(json: String?) {
    guard !finished else { return }
    finished = true
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      self.dismiss(animated: true) { self.onResult(json) }
    }
  }

  private func show(hint: String, votes: String?) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      self.hintLabel.text = hint
      if let v = votes {
        self.votesLabel.text = v
        self.votesLabel.isHidden = false
      } else {
        self.votesLabel.isHidden = true
      }
    }
  }

  private func setFallbackVisible(_ visible: Bool) {
    DispatchQueue.main.async { [weak self] in
      self?.fallbackButton.isHidden = !visible
    }
  }
}

// MARK: - تحليل الإطارات

extension LicenceScannerViewController: AVCaptureVideoDataOutputSampleBufferDelegate {

  func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard !finished, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

    // الصورة تنقرأ بـ orientation: .right (تدوير 90°)، فإحداثيات Vision
    // نسبية للصورة بعد التدوير — يعني العرض هو ارتفاع البافر والعكس
    let width = CVPixelBufferGetHeight(buffer)
    let height = CVPixelBufferGetWidth(buffer)

    let request = VNRecognizeTextRequest { [weak self] req, _ in
      guard let self = self, !self.finished,
            let obs = req.results as? [VNRecognizedTextObservation] else { return }

      // Vision يعطي إحداثيات معيارية (0..1) مقلوبة رأسياً —
      // نحوّلها لبكسلات بنفس اتجاه الشاشة
      var blocks: [TextBlock] = []
      var lines: [String] = []

      for o in obs {
        guard let text = o.topCandidates(1).first?.string else { continue }
        lines.append(text)

        let box = o.boundingBox
        blocks.append(
          TextBlock(
            text: text,
            left: Int(box.minX * CGFloat(width)),
            top: Int((1 - box.maxY) * CGFloat(height)),
            right: Int(box.maxX * CGFloat(width)),
            bottom: Int((1 - box.minY) * CGFloat(height))
          )
        )
      }

      self.frames += 1
      let raw = lines.joined(separator: "\n")

      switch self.side {
      case .front: self.handleFront(raw)
      case .back: self.handleBack(blocks: blocks, raw: raw)
      }
    }

    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false   // الـ MRZ مو لغة طبيعية
    request.recognitionLanguages = ["en-US"]

    let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .right, options: [:])
    try? handler.perform([request])
  }

  // MARK: الوجه

  private func handleFront(_ raw: String) {
    let parsed = LicenceParser.parseFront(raw)

    guard let mrz = parsed.mrz else {
      if bestViz == nil || parsed.viz.richness > bestViz!.viz.richness {
        bestViz = parsed
      }
      show(hint: "ابحث عن السطر السفلي للبطاقة", votes: nil)
      if frames > fallbackAfterFrames && bestViz != nil { setFallbackVisible(true) }
      return
    }

    let key = mrz.raw
    let count = (votes[key] ?? 0) + 1
    votes[key] = count

    if bestFront[key] == nil || parsed.viz.richness > bestFront[key]!.viz.richness {
      bestFront[key] = parsed
    }

    show(hint: "ثبّت البطاقة — جاري التأكيد", votes: "\(count) / \(frontVotes)")
    setFallbackVisible(false)

    if count >= frontVotes {
      finish(json: LicenceJson.front(bestFront[key] ?? parsed))
    }
  }

  // MARK: الظهر

  private func handleBack(blocks: [TextBlock], raw: String) {
    let found = LicenceParser.parseBack(blocks: blocks, rawText: raw)

    guard !found.isEmpty else {
      show(hint: "وجّه الكاميرا على جدول الفئات", votes: nil)
      return
    }

    let key = found.map { "\($0.code):\($0.issueDate):\($0.expiryDate)" }.joined(separator: "|")
    let count = (votes[key] ?? 0) + 1
    votes[key] = count

    show(hint: "لقينا: " + found.map { $0.code }.joined(separator: "، "),
         votes: "\(count) / \(backVotes)")

    if count >= backVotes {
      finish(json: LicenceJson.back(found))
    }
  }
}
