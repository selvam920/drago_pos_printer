package com.example.drago_pos_printer.bluetooth
import io.flutter.plugin.common.MethodChannel.Result

interface IBluetoothConnection {
    fun connect(address: String, result: Result)
    fun stop()
    fun write(out: ByteArray?)
    var state: Int
}