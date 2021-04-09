package com.sogeti.CoinCounter

import android.Manifest
import android.app.AlertDialog
import android.content.Context
import android.content.DialogInterface
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.*
import android.hardware.camera2.*
import android.media.Image
import android.media.ImageReader
import android.net.Uri
import androidx.appcompat.app.AppCompatActivity
import android.os.Bundle
import android.os.Handler
import android.os.HandlerThread
import android.provider.Settings
import android.util.Size
import android.view.Surface
import android.view.TextureView
import android.view.View
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.RelativeLayout
import androidx.core.content.ContextCompat
import com.google.firebase.FirebaseApp
import com.google.firebase.ml.common.modeldownload.FirebaseLocalModel
import com.google.firebase.ml.common.modeldownload.FirebaseModelManager
import com.google.firebase.ml.custom.*
import java.util.*
import java.util.concurrent.Semaphore
import java.util.concurrent.TimeUnit
import kotlin.collections.HashMap
import kotlin.math.max
import kotlin.math.min

class MainActivity : AppCompatActivity() {

    private val permissions = arrayOf(Manifest.permission.CAMERA)

    private lateinit var cameraView: TextureView
    private lateinit var cropSquare: View

    private var backgroundThread: HandlerThread? = null
    private var backgroundHandler: Handler? = null
    private val cameraOpenCloseLock = Semaphore(1)

    private var previewSize = Size(0,0)
    private var camera = ""
    private var sensorOrientation = 0
    private var capturingImage = false
    private var isPaused = false

    private var cameraDevice: CameraDevice? = null
    private var captureSession: CameraCaptureSession? = null
    private var imageReader: ImageReader? = null
    private var previewRequestBuilder: CaptureRequest.Builder? = null

    private var modelName = "CoinClassifierV5"
    private var interpreter: FirebaseModelInterpreter? = null
    private var labels = arrayOf("AUD2", "EUR0.05", "EUR0.1", "EUR0.2", "EUR0.5", "EUR1", "EUR2", "NZD1", "USD0.25", "dump")
    private var inputShape = intArrayOf(1, 299, 299, 3)
    private var outputShape = intArrayOf(1, labels.size)
    private var modelPrecision = FirebaseModelDataType.FLOAT32

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        initFirebase()

        cameraView = findViewById(R.id.camera_view)
        cropSquare = findViewById(R.id.crop_square)

        val askPermissions = permissions.filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
        if (askPermissions.isNotEmpty()) { requestPermissions(askPermissions.toTypedArray(), 0) }
    }

    private fun initFirebase() {
        FirebaseApp.initializeApp(this)

        val path = assets.list("")?.firstOrNull { it.contains(modelName) } ?: return
        val source = FirebaseLocalModel.Builder(modelName).setAssetFilePath(path).build()
        FirebaseModelManager.getInstance().registerLocalModel(source)

        val options = FirebaseModelOptions.Builder().setLocalModelName(modelName).build()
        interpreter = FirebaseModelInterpreter.getInstance(options)
    }


    override fun onResume() {
        super.onResume()

        startBackgroundThread()

        if (cameraView.isAvailable) startCameraSession(Size(cameraView.width, cameraView.height))
        cameraView.surfaceTextureListener = surfaceTextureListener

    }

    override fun onPause() {
        stopCameraSession()
        stopBackgroundThread()
        super.onPause()
    }

    private fun showMoney(money: Money) {
        isPaused = true

        val listener = DialogInterface.OnClickListener { _, _ ->
            isPaused = false
            labelHistory = ArrayList()
        }

        AlertDialog.Builder(this)
            .setMessage(money.id)
            .setNeutralButton("Ok", listener)
            .show()
    }

    //MARK: Camera

    private fun createCameraPreviewSession() {
        val texture = cameraView.surfaceTexture
        texture.setDefaultBufferSize(previewSize.width, previewSize.height)

        val surface = Surface(texture)
        previewRequestBuilder = cameraDevice?.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW)
        previewRequestBuilder?.addTarget(surface)

        cameraDevice?.createCaptureSession(listOf(surface, imageReader?.surface), captureStateCallback, null)
    }

    private fun stopCameraSession() {
        cameraOpenCloseLock.acquire()
        captureSession?.close()
        captureSession = null
        cameraDevice?.close()
        cameraDevice = null
        imageReader?.close()
        imageReader = null
        cameraOpenCloseLock.release()
    }

    private fun startCameraSession(surfaceSize: Size) {
        if (checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) return

        val manager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
        if (manager.cameraIdList.isEmpty()) return

        camera = getCameraID(manager.cameraIdList, manager) ?: return


        val w = inputShape[1] * cameraView.width / cropSquare.width
        val h = inputShape[2] * cameraView.height / cropSquare.height

        val outputSize = getOptimalSize(manager, Size(w, h)) ?: return

        imageReader = ImageReader.newInstance(outputSize.width, outputSize.height, ImageFormat.JPEG, 1)
        imageReader?.apply { setOnImageAvailableListener(onImageAvailableListener, backgroundHandler) }


        previewSize = getOptimalSize(manager, surfaceSize) ?: return

        configureTransform(surfaceSize)

        if (!cameraOpenCloseLock.tryAcquire(2500, TimeUnit.MILLISECONDS)) return

        manager.openCamera(camera, deviceStateCallback, backgroundHandler)

    }

    private fun configureTransform(surfaceSize: Size) {
        val rotation = windowManager?.defaultDisplay?.rotation ?: Surface.ROTATION_0
        val matrix = Matrix()
        val viewRect = RectF(0f, 0f, surfaceSize.width.toFloat(), surfaceSize.height.toFloat())
//        val bufferRect = RectF(0f, 0f, previewSize.height.toFloat(), previewSize.width.toFloat())
        val centerX = viewRect.centerX()
        val centerY = viewRect.centerY()
        if (Surface.ROTATION_180 == rotation) matrix.postRotate(180f, centerX, centerY)
        cameraView.setTransform(matrix)
    }

    private fun getOptimalSize(manager: CameraManager, surfaceSize: Size): Size? {
        val characteristics = manager.getCameraCharacteristics(camera)

        sensorOrientation = characteristics.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 0
        val swappedDimensions = (sensorOrientation == 90 || sensorOrientation == 270)

        val displaySize = Point()
        windowManager?.defaultDisplay?.getSize(displaySize)

        val rotatedPreviewWidth = if (swappedDimensions) surfaceSize.height else surfaceSize.width
        val rotatedPreviewHeight = if (swappedDimensions) surfaceSize.width else surfaceSize.height
        var maxPreviewWidth = if (swappedDimensions) displaySize.y else displaySize.x
        var maxPreviewHeight = if (swappedDimensions) displaySize.x else displaySize.y

        if (maxPreviewWidth > 1920) maxPreviewWidth = 1920
        if (maxPreviewHeight > 1080) maxPreviewHeight = 1080

        val map = characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP) ?: return null
        val sizes = map.getOutputSizes(SurfaceTexture::class.java)
            .filter { x -> (x.width <= maxPreviewWidth && x.height <= maxPreviewHeight) }
        val bigEnough = ArrayList<Size>()
        val notBigEnough = ArrayList<Size>()
        sizes.forEach { x -> if (x.width >= rotatedPreviewWidth && x.height >= rotatedPreviewHeight) bigEnough.add(x) else notBigEnough.add(x) }

        if (bigEnough.isNotEmpty()) return bigEnough.minBy { it.width.toLong() * it.height }
        if (notBigEnough.isNotEmpty()) return notBigEnough.maxBy { it.width.toLong() * it.height }
        return null
    }

//    private fun getLargestImageSize(manager: CameraManager): Size? {
//        val characteristics = manager.getCameraCharacteristics(camera)
//        val map = characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP) ?: return null
//        return listOf(*map.getOutputSizes(ImageFormat.JPEG)).maxBy { it.width.toLong() * it.height }
//    }


    private fun getCameraID(list: Array<String>, manager: CameraManager): String? {
        for (id in list) {
            val characteristics = manager.getCameraCharacteristics(id)
            val cameraDirection = characteristics.get(CameraCharacteristics.LENS_FACING)
            if (cameraDirection == null || cameraDirection != CameraCharacteristics.LENS_FACING_BACK) continue
            if (characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP) == null) continue

            return id
        }

        return null
    }

    private fun captureStillImage() {
        capturingImage = true
        val surface = imageReader?.surface ?: return
        val rotation = windowManager?.defaultDisplay?.rotation ?: 0
        val captureBuilder = cameraDevice?.createCaptureRequest(
            CameraDevice.TEMPLATE_STILL_CAPTURE)?.apply {
            addTarget(surface)

            set(CaptureRequest.JPEG_ORIENTATION, (rotation + sensorOrientation) % 360)

            set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE)
        }

        val request = captureBuilder?.build() ?: return
        captureSession?.apply { capture(request, captureCallback, null) }
    }

    private fun getBitmap(image: Image): Bitmap {
        val buffer = image.planes[0].buffer
        val bytes = ByteArray(buffer.remaining())
        buffer.get(bytes)

        var bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, null)

        val matrix = Matrix()
        if (bitmap.height < bitmap.width) matrix.postRotate(90f)


        bitmap = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)

        val cropWidth = cropSquare.width.toFloat()
        val cropHeight = cropSquare.height.toFloat()
        val textureWidth = cameraView.width.toFloat()
        val textureHeight = cameraView.height.toFloat()
        val imageWidth = bitmap.width.toFloat()
        val imageHeight = bitmap.height.toFloat()

        val xPercentage = cropWidth / textureWidth
        val yPercentage = cropHeight / textureHeight

        val imageAspect = imageWidth / imageHeight
        val screenAspect = textureWidth / textureHeight

        val w = if (screenAspect > imageAspect) imageWidth * xPercentage else imageHeight * yPercentage
        val h = w

        val x = imageWidth * 0.5 - w * 0.5
        val y = imageHeight * 0.5 - h * 0.5

        return Bitmap.createBitmap(bitmap, x.toInt(), y.toInt(), w.toInt(), h.toInt())//, matrix, true)
    }

    private var captureStateCallback = object : CameraCaptureSession.StateCallback() {
        override fun onConfigureFailed(cameraCaptureSession: CameraCaptureSession) {}

        override fun onConfigured(cameraCaptureSession: CameraCaptureSession) {
            if (cameraDevice == null) return
            captureSession = cameraCaptureSession

            previewRequestBuilder?.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE)

            val previewRequest = previewRequestBuilder?.build() ?: return
            captureSession?.setRepeatingRequest(previewRequest, captureCallback, backgroundHandler)

        }
    }

    private val deviceStateCallback = object : CameraDevice.StateCallback() {

        override fun onOpened(cameraDevice: CameraDevice) {
            cameraOpenCloseLock.release()
            this@MainActivity.cameraDevice = cameraDevice
            createCameraPreviewSession()
        }

        override fun onDisconnected(cameraDevice: CameraDevice) {
            cameraOpenCloseLock.release()
            cameraDevice.close()
            this@MainActivity.cameraDevice = null
        }

        override fun onError(cameraDevice: CameraDevice, error: Int) {
            onDisconnected(cameraDevice)
            finish()
        }
    }

    private val captureCallback = object : CameraCaptureSession.CaptureCallback() {

        private fun process() {
            if (!capturingImage) captureStillImage()
        }

        override fun onCaptureProgressed(session: CameraCaptureSession, request: CaptureRequest, partialResult: CaptureResult) {
            process()
        }

        override fun onCaptureCompleted(session: CameraCaptureSession, request: CaptureRequest, result: TotalCaptureResult) {
            process()
        }

    }

    private val onImageAvailableListener = ImageReader.OnImageAvailableListener {
        backgroundHandler?.post {
            val bitmap = it.acquireNextImage().use { getBitmap(it) }
            if (isPaused) {
                capturingImage = false
                return@post
            }
            val id = analyze(bitmap) ?: ""
            val money = Money(id)
            if (money.isValid) runOnUiThread { showMoney(money) }
            capturingImage = false
        }
    }

    //MARK: MachineLearning

    private var labelHistory: ArrayList<Pair<Bitmap, String>> = ArrayList()
    private val maxHistory = 3

    private fun analyze(bitmap: Bitmap): String? {
        val i = interpreter ?: return null

        val pixels = Bitmap.createScaledBitmap(bitmap, inputShape[1], inputShape[2], true)

        val input = Array(inputShape[0]) { Array(inputShape[1]) { Array(inputShape[2]) { FloatArray(inputShape[3]) } } }
        for (x in 0 until inputShape[1]) {
            for (y in 0 until inputShape[2]) {
                val pixel = pixels.getPixel(x, y)
                input[0][x][y][0] = Color.red(pixel) / 255.0f
                input[0][x][y][1] = Color.green(pixel) / 255.0f
                input[0][x][y][2] = Color.blue(pixel) / 255.0f
            }
        }

        val inputs = FirebaseModelInputs.Builder().add(input).build()

        val options = FirebaseModelInputOutputOptions.Builder()
            .setInputFormat(0, modelPrecision, inputShape)
            .setOutputFormat(0,modelPrecision, outputShape)
            .build()

        val semaphore = Semaphore(0)
        var result = FirebaseModelOutputs(hashMapOf())
        i.run(inputs, options).addOnSuccessListener { result = it; semaphore.release() }
        semaphore.acquire()

        val output = result.getOutput<Array<FloatArray>>(0)[0]
        val observations = output.indices.map { Pair(labels[it], output[it]) }
        val max = observations.maxBy { it.second } ?: return null

        labelHistory.add(Pair(bitmap, max.first))
        while (labelHistory.size > maxHistory) { labelHistory.removeAt(0) }
        val counts: HashMap<String, Int> = HashMap()
        labelHistory.forEach { counts.put(it.second, counts.getOrDefault(it.second, 0) + 1) }//{ if let id = $0.1 { counts[id] = (counts[id] ?? 0) + 1 } }
        val (value, count) = counts.maxBy { it.value } ?: return null
        if (count < 3) return null

        return value
    }

    //MARK: SurfaceTexture

    private val surfaceTextureListener = object : TextureView.SurfaceTextureListener {

        override fun onSurfaceTextureAvailable(texture: SurfaceTexture, width: Int, height: Int) {
            startCameraSession(Size(width, height))
        }

        override fun onSurfaceTextureSizeChanged(texture: SurfaceTexture, width: Int, height: Int) {
            configureTransform(Size(width, height))
        }

        override fun onSurfaceTextureDestroyed(texture: SurfaceTexture) = true
        override fun onSurfaceTextureUpdated(texture: SurfaceTexture) = Unit
    }

    //MARK: PermissionActivity Result

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)


        for (permission in permissions) {
            if (checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) continue
            if (!shouldShowRequestPermissionRationale(permission)) continue
            val intent = Intent()
            intent.action = Settings.ACTION_APPLICATION_DETAILS_SETTINGS
            intent.data = Uri.fromParts("package", packageName, null)
            startActivity(intent)
            break
        }
    }

    //MARK: Background

    private fun startBackgroundThread() {
        backgroundThread = HandlerThread("cameraBackgroundThread").also { it.start() }
        val looper = backgroundThread?.looper ?: return
        backgroundHandler = Handler(looper)
    }

    private fun stopBackgroundThread() {
        backgroundThread?.quitSafely()
        backgroundThread?.join()
        backgroundThread = null
        backgroundHandler = null

    }
}
