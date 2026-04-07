package com.example.drago_pos_printer.adapter

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.*
import android.util.Base64
import android.util.Log
import android.widget.Toast
import com.example.drago_pos_printer.R
import com.example.drago_pos_printer.usb.USBPrinterService
import java.nio.charset.Charset
import java.util.*
import kotlin.math.min

class USBPrinterAdapter private constructor() {

    private var mContext: Context? = null
    private var mUSBManager: UsbManager? = null
    private var mPermissionIndent: PendingIntent? = null
    private var mUsbDevice: UsbDevice? = null
    private var mUsbDeviceConnection: UsbDeviceConnection? = null
    private var mUsbInterface: UsbInterface? = null
    private var mEndPoint: UsbEndpoint? = null

    fun init(reactContext: Context?) {
        mContext = reactContext
        mUSBManager = mContext!!.getSystemService(Context.USB_SERVICE) as UsbManager
        mPermissionIndent = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
            PendingIntent.getBroadcast(mContext, 0, Intent(ACTION_USB_PERMISSION), PendingIntent.FLAG_MUTABLE)
        } else {
            PendingIntent.getBroadcast(mContext, 0, Intent(ACTION_USB_PERMISSION), 0)
        }
        val filter = IntentFilter(ACTION_USB_PERMISSION)
        filter.addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
        mContext!!.registerReceiver(mUsbDeviceReceiver, filter)
        Log.v(LOG_TAG, "ESC/POS Printer initialized")
    }


    private val mUsbDeviceReceiver: BroadcastReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val action = intent.action
            if ((ACTION_USB_PERMISSION == action)) {
                synchronized(this) {
                    val usbDevice: UsbDevice? = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
                    if (intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)) {
                        Log.i(
                            LOG_TAG,
                            "Success get permission for device " + usbDevice!!.deviceId + ", vendor_id: " + usbDevice.vendorId + " product_id: " + usbDevice.productId
                        )
                        mUsbDevice = usbDevice
                    } else {
                        Toast.makeText(
                            context, mContext?.getString(R.string.user_refuse_perm) + ": ${usbDevice!!.deviceName}",
                            Toast.LENGTH_LONG
                        ).show()
                    }
                }
            } else if ((UsbManager.ACTION_USB_DEVICE_DETACHED == action)) {
                if (mUsbDevice != null) {
                    Toast.makeText(context, mContext?.getString(R.string.device_off), Toast.LENGTH_LONG).show()
                    closeConnectionIfExists()
                }
            }
        }
    }


    fun closeConnectionIfExists() {
        if (mUsbDeviceConnection != null) {
            mUsbDeviceConnection!!.releaseInterface(mUsbInterface)
            mUsbDeviceConnection!!.close()
            mUsbInterface = null
            mEndPoint = null
            mUsbDeviceConnection = null
        }
    }

    val deviceList: List<UsbDevice>
        get() {
            if (mUSBManager == null) {
                Toast.makeText(mContext, mContext?.getString(R.string.not_usb_manager), Toast.LENGTH_LONG).show()
                return emptyList()
            }
            return ArrayList(mUSBManager!!.deviceList.values)
        }

    fun selectDevice(vendorId: Int, productId: Int): Boolean {
        if ((mUsbDevice == null) || (mUsbDevice!!.vendorId != vendorId) || (mUsbDevice!!.productId != productId)) {
            synchronized(printLock) {
                closeConnectionIfExists()
                val usbDevices: List<UsbDevice> = deviceList
                for (usbDevice: UsbDevice in usbDevices) {
                    if ((usbDevice.vendorId == vendorId) && (usbDevice.productId == productId)) {
                        Log.v(
                            LOG_TAG,
                            "Request for device: vendor_id: " + usbDevice.vendorId + ", product_id: " + usbDevice.productId
                        )
                        closeConnectionIfExists()
                        mUSBManager!!.requestPermission(usbDevice, mPermissionIndent)
                        return true
                    }
                }
                return false
            }
        }
        return true
    }

    private fun openConnection(): Boolean {
        if (mUsbDevice == null) {
            Log.e(LOG_TAG, "USB Deivce is not initialized")
            return false
        }
        if (mUSBManager == null) {
            Log.e(LOG_TAG, "USB Manager is not initialized")
            return false
        }
        if (mUsbDeviceConnection != null) {
            Log.i(LOG_TAG, "USB Connection already connected")
            return true
        }
        val usbInterface = mUsbDevice!!.getInterface(0)
        for (i in 0 until usbInterface.endpointCount) {
            val ep = usbInterface.getEndpoint(i)
            if (ep.type == UsbConstants.USB_ENDPOINT_XFER_BULK) {
                if (ep.direction == UsbConstants.USB_DIR_OUT) {
                    val usbDeviceConnection = mUSBManager!!.openDevice(mUsbDevice)
                    if (usbDeviceConnection == null) {
                        Log.e(LOG_TAG, "Failed to open USB Connection")
                        return false
                    }
                    Toast.makeText(mContext,  mContext?.getString(R.string.connected_device), Toast.LENGTH_SHORT).show()
                    if (usbDeviceConnection.claimInterface(usbInterface, true)) {
                        mEndPoint = ep
                        mUsbInterface = usbInterface
                        mUsbDeviceConnection = usbDeviceConnection
                        return true
                    } else {
                        usbDeviceConnection.close()
                        Log.e(LOG_TAG, "Failed to retrieve usb connection")
                        return false
                    }
                }
            }
        }
        return true
    }

    fun printText(text: String): Boolean {
        Log.v(LOG_TAG, "Printing text")
        val isConnected = openConnection()
        if (isConnected) {
            Log.v(LOG_TAG, "Connected to device")
            Thread(Runnable {
                synchronized(printLock) {
                    val bytes: ByteArray = text.toByteArray(Charset.forName("UTF-8"))
                    sendChunked(bytes)
                }
            }).start()
            return true
        } else {
            Log.v(LOG_TAG, "Failed to connect to device")
            return false
        }
    }

    fun printRawData(data: String): Boolean {
        Log.v(LOG_TAG, "Printing raw data")
        val isConnected = openConnection()
        if (isConnected) {
            Log.v(LOG_TAG, "Connected to device")
            Thread {
                synchronized(printLock) {
                    val bytes: ByteArray = Base64.decode(data, Base64.DEFAULT)
                    sendChunked(bytes)
                }
            }.start()
            return true
        } else {
            Log.v(LOG_TAG, "Failed to connected to device")
            return false
        }
    }

    fun printBytes(bytes: ArrayList<Int>): Boolean {
        Log.v(LOG_TAG, "Printing bytes")
        val isConnected = openConnection()
        if (isConnected) {
            Log.v(LOG_TAG, "Connected to device")
            Thread {
                synchronized(printLock) {
                    val bytedata = ByteArray(bytes.size) { bytes[it].toByte() }
                    sendChunked(bytedata)
                }
            }.start()
            return true
        } else {
            Log.v(LOG_TAG, "Failed to connected to device")
            return false
        }
    }

    private fun bulkTransferWithRetry(buffer: ByteArray, length: Int, maxRetries: Int = 3): Int {
        for (attempt in 0 until maxRetries) {
            val result = mUsbDeviceConnection!!.bulkTransfer(mEndPoint, buffer, length, 100000)
            if (result >= 0) return result
            Log.w(LOG_TAG, "bulkTransfer failed (attempt ${attempt + 1}/$maxRetries, error $result, length $length)")
            try { Thread.sleep(50L * (attempt + 1)) } catch (_: InterruptedException) {}
        }
        return -1
    }

    private fun sendChunked(data: ByteArray) {
        if (mUsbDeviceConnection == null || mEndPoint == null) {
            Log.e(LOG_TAG, "No USB connection or endpoint")
            return
        }
        val chunkSize = mEndPoint!!.maxPacketSize
        val totalSize = data.size
        var offset = 0
        while (offset < totalSize) {
            val length = min(chunkSize, totalSize - offset)
            val buffer = data.copyOfRange(offset, offset + length)
            val b = bulkTransferWithRetry(buffer, length)
            if (b < 0) {
                Log.e(LOG_TAG, "bulk transfer failed at offset $offset (error $b, chunkSize $chunkSize)")
                return
            }
            offset += length
        }
        Log.i(LOG_TAG, "sendChunked complete, totalSize: $totalSize")
    }

    companion object {
        private var mInstance: USBPrinterAdapter? = null
        private const val ACTION_USB_PERMISSION = "com.example.drago_pos_printer.USB_PERMISSION"
        private const val LOG_TAG = "ESC POS Printer"
        private val printLock = Any()
        val instance: USBPrinterAdapter
            get() {
                if (mInstance == null) {
                    mInstance = USBPrinterAdapter()
                }
                return mInstance!!
            }
    }
}