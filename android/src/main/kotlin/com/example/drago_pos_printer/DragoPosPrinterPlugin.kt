package com.example.drago_pos_printer

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.usb.UsbDevice
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Message
import android.util.Log
import android.widget.Toast
import androidx.annotation.NonNull
import androidx.core.app.ActivityCompat
import androidx.core.app.ActivityCompat.startActivityForResult
import com.example.drago_pos_printer.bluetooth.BluetoothConnection
import com.example.drago_pos_printer.bluetooth.BluetoothConstants
import com.example.drago_pos_printer.bluetooth.BluetoothService
import com.example.drago_pos_printer.bluetooth.BluetoothService.Companion.TAG
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry
import io.flutter.plugin.common.BinaryMessenger

/** DragoPosPrinterPlugin */
class DragoPosPrinterPlugin : FlutterPlugin, MethodCallHandler, PluginRegistry.RequestPermissionsResultListener,
    PluginRegistry.ActivityResultListener,
    ActivityAware {
    /// The MethodChannel that will the communication between Flutter and native Android
    ///
    /// This local reference serves to register the plugin with the Flutter Engine and unregister it
    /// when the Flutter Engine is detached from the Activity

    private final var TAG = "DragoPosPrinterPlugin"

    private var binaryMessenger: BinaryMessenger? = null

    private var channel: MethodChannel? = null
    private var messageChannel: EventChannel? = null
    private var messageUSBChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null

    // Declare our eventSink later it will be initialized
    private var eventUSBSink: EventChannel.EventSink? = null
    private var context: Context? = null
    private var currentActivity: Activity? = null
    private var requestPermissionBT: Boolean = false
    private var isBle: Boolean = false
    private var isScan: Boolean = false
    private lateinit var bluetoothService: BluetoothService

    private val bluetoothHandler = object : Handler(Looper.getMainLooper()) {

        private val bluetoothStatus: Int
            get() = BluetoothService.bluetoothConnection?.state ?: 99

        override fun handleMessage(msg: Message) {
            super.handleMessage(msg)
            when (msg.what) {
                BluetoothConstants.MESSAGE_STATE_CHANGE -> {
                    when (bluetoothStatus) {
                        BluetoothConstants.STATE_CONNECTED -> {
                            Log.w(TAG, " -------------------------- connection BT STATE_CONNECTED ")
                            if (msg.obj != null)
                                try {
                                    val result = msg.obj as Result?
                                    result?.success(true)
                                } catch (e: Exception) {
                                }
                            eventSink?.success(2)
                            bluetoothService.removeReconnectHandlers()
                        }
                        BluetoothConstants.STATE_CONNECTING -> {
                            Log.w(TAG, " -------------------------- connection BT STATE_CONNECTING ")
                            eventSink?.success(1)
                        }
                        BluetoothConstants.STATE_NONE -> {
                            Log.w(TAG, " -------------------------- connection BT STATE_NONE ")
                            eventSink?.success(0)
                            bluetoothService.autoConnectBt()

                        }
                        BluetoothConstants.STATE_FAILED -> {
                            Log.w(TAG, " -------------------------- connection BT STATE_FAILED ")
                            if (msg.obj != null)
                                try {
                                    val result = msg.obj as Result?
                                    result?.success(false)
                                } catch (e: Exception) {
                                }
                            eventSink?.success(0)
                        }
                    }
                }
                BluetoothConstants.MESSAGE_WRITE -> {
//                val readBuf = msg.obj as ByteArray
//                Log.d("bluetooth", "envia bt: ${String(readBuf)}")
                }
                BluetoothConstants.MESSAGE_READ -> {
                    val readBuf = msg.obj as ByteArray
                    var readMessage = String(readBuf, 0, msg.arg1)
                    readMessage = readMessage.trim { it <= ' ' }
                    Log.d("bluetooth", "receive bt: $readMessage")
                }
                BluetoothConstants.MESSAGE_DEVICE_NAME -> {
                    val deviceName = msg.data.getString(BluetoothConstants.DEVICE_NAME)
                    Log.d("bluetooth", " ------------- deviceName $deviceName -----------------")
                }

                BluetoothConstants.MESSAGE_TOAST -> {
                    val bundle = msg.data
                    bundle?.getInt(BluetoothConnection.TOAST)?.let {
                        Toast.makeText(context, context!!.getString(it), Toast.LENGTH_SHORT).show()
                    }
                }
                BluetoothConstants.MESSAGE_START_SCANNING -> {

                }

                BluetoothConstants.MESSAGE_STOP_SCANNING -> {

                }
                99 -> {

                }

            }
        }

    }



    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        Log.d(TAG, "onAttachedToEngine")
        binaryMessenger = flutterPluginBinding.binaryMessenger
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        Log.d(TAG, "onDetachedFromEngine")
        channel?.setMethodCallHandler(null)
        messageChannel?.setStreamHandler(null)
        messageUSBChannel?.setStreamHandler(null)

        messageChannel = null
        messageUSBChannel = null

        if (this::bluetoothService.isInitialized) {
            bluetoothService.setHandler(null)
        }
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        Log.d(TAG, "onAttachedToActivity")

        context = binding.activity.applicationContext
        currentActivity = binding.activity

        if (binaryMessenger == null) {
            Log.e(TAG, "binaryMessenger is not initialized. Did you forget to call onAttachedToEngine?")
            return
        }

        channel = MethodChannel(binaryMessenger!!, methodChannel)
        channel!!.setMethodCallHandler(this)

        messageChannel = EventChannel(binaryMessenger!!, eventChannelBT)
        messageChannel?.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(p0: Any?, sink: EventChannel.EventSink) {
                eventSink = sink
            }
            override fun onCancel(p0: Any?) {
                eventSink = null
            }
        })

        messageUSBChannel = EventChannel(binaryMessenger!!, eventChannelUSB)
        messageUSBChannel?.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(p0: Any?, sink: EventChannel.EventSink) {
                eventUSBSink = sink
            }
            override fun onCancel(p0: Any?) {
                eventUSBSink = null
            }
        })

        bluetoothService = BluetoothService.getInstance(bluetoothHandler)

        binding.addRequestPermissionsResultListener(this)
        binding.addActivityResultListener(this)
        bluetoothService.setActivity(currentActivity)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        Log.d(TAG, "onDetachedFromActivityForConfigChanges")
        currentActivity = null
        bluetoothService.setActivity(null)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        Log.d(TAG, "onReattachedToActivityForConfigChanges")
        currentActivity = binding.activity
        binding.addRequestPermissionsResultListener(this)
        binding.addActivityResultListener(this)
        bluetoothService.setActivity(currentActivity)
    }

    override fun onDetachedFromActivity() {
        Log.d(TAG, "onDetachedFromActivity")
        currentActivity = null
        bluetoothService.setActivity(null)
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        isScan = false
        Log.d(TAG, "method call " + call.method.toString())
        when {
            call.method.equals("getBluetoothList") -> {
                isBle = false
                isScan = true
                if (verifyIsBluetoothIsOn()) {
                    bluetoothService.cleanHandlerBtBle()
                    result.success(bluetoothService.scanBluDevice())
                }
            }
            call.method.equals("getBluetoothLeList") -> {
                isBle = true
                isScan = true
                if (verifyIsBluetoothIsOn()) {
                    bluetoothService.scanBleDevice(channel!!)
                    result.success(null)
                }
            }

            call.method.equals("onStartConnection") -> {
                val address: String? = call.argument("address")
                val isBle: Boolean? = call.argument("isBle")
                val autoConnect: Boolean = if (call.hasArgument("autoConnect")) call.argument("autoConnect")!! else false
                if (verifyIsBluetoothIsOn()) {
                    bluetoothService.setHandler(bluetoothHandler)
                    bluetoothService.onStartConnection(context!!, address!!, result, isBle = isBle!!, autoConnect = autoConnect)
                } else {
                    result.success(false)
                }
            }

            call.method.equals("disconnect") -> {
                try {
                    bluetoothService.setHandler(bluetoothHandler)
                    bluetoothService.bluetoothDisconnect()
                    result.success(true)
                } catch (e: Exception) {
                    result.success(false)
                }

            }

            call.method.equals("sendDataByte") -> {
                if (verifyIsBluetoothIsOn()) {
                    bluetoothService.setHandler(bluetoothHandler)
                    val listInt: ArrayList<Int>? = call.argument("bytes")
                    val ints = listInt!!.toIntArray()
                    val bytes = ints.foldIndexed(ByteArray(ints.size)) { i, a, v -> a.apply { set(i, v.toByte()) } }
                    val res = bluetoothService.sendDataByte(bytes)
                    result.success(res)
                } else {
                    result.success(false)
                }
            }
            call.method.equals("sendText") -> {
                if (verifyIsBluetoothIsOn()) {
                    val text: String? = call.argument("text")
                    bluetoothService.sendData(text!!)
                    result.success(true)
                } else {
                    result.success(false)
                }
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    private fun verifyIsBluetoothIsOn(): Boolean {
        if (checkPermissions()) {
            if (!this::bluetoothService.isInitialized){
                bluetoothService = BluetoothService.getInstance(bluetoothHandler)
            }
            if (!bluetoothService.mBluetoothAdapter.isEnabled) {
                if (requestPermissionBT) return false
                val enableBtIntent = Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE)
                currentActivity?.let { startActivityForResult(it, enableBtIntent, PERMISSION_ENABLE_BLUETOOTH, null) }
                requestPermissionBT = true
                return false
            }
        } else return false
        return true
    }



    private fun checkPermissions(): Boolean {
        val permissions = mutableListOf(
            Manifest.permission.ACCESS_FINE_LOCATION,
//            Manifest.permission.BLUETOOTH,
//            Manifest.permission.BLUETOOTH_ADMIN,
        )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            permissions.add(Manifest.permission.BLUETOOTH_SCAN)
            permissions.add(Manifest.permission.BLUETOOTH_CONNECT)
        }

        if (!hasPermissions(context, *permissions.toTypedArray())) {
            Log.d(TAG, "")
            ActivityCompat.requestPermissions(currentActivity!!, permissions.toTypedArray(), PERMISSION_ALL)
            return false
        }
        return true
    }

    private fun hasPermissions(context: Context?, vararg permissions: String?): Boolean {
        if (context != null) {
            for (permission in permissions) {
                if (ActivityCompat.checkSelfPermission(context, permission!!) != PackageManager.PERMISSION_GRANTED) {
                    return false
                }
            }
        }
        return true
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        when (requestCode) {
            PERMISSION_ENABLE_BLUETOOTH -> {
                requestPermissionBT = false

                Log.d(TAG, "PERMISSION_ENABLE_BLUETOOTH PERMISSION_GRANTED resultCode $resultCode")
//                if (resultCode == Activity.RESULT_OK)
//                    if (isScan)
//                        if (isBle) bluetoothService.scanBleDevice(channel!!) else bluetoothService.scanBluDevice()

            }
        }
        return true
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray): Boolean {
        Log.d(TAG, " --- requestCode $requestCode")
        when (requestCode) {

            PERMISSION_ALL -> {
                var grant = true
                grantResults.forEach { permission ->

                    val permissionGranted = grantResults.isNotEmpty() &&
                            permission == PackageManager.PERMISSION_GRANTED
                    Log.d(TAG, " --- requestCode $requestCode permission $permission permissionGranted $permissionGranted")
                    if (!permissionGranted) grant = false

                }
                if (!grant) {
                    Toast.makeText(context, R.string.not_permissions, Toast.LENGTH_LONG).show()
                } else {
//                    if (verifyIsBluetoothIsOn() && isScan)
//                        if (isBle) bluetoothService.scanBleDevice(channel!!) else bluetoothService.scanBluDevice(channel!!)
                }
                return true
            }
        }
        return false
    }

    companion object {
        const val PERMISSION_ALL = 1
        const val PERMISSION_ENABLE_BLUETOOTH = 999
        const val methodChannel = "com.example.drago_pos_printer"
        const val eventChannelBT = "com.example.drago_pos_printer/bt_state"
        const val eventChannelUSB = "com.example.drago_pos_printer/usb_state"

    }
}
