package com.adnanhasgul.akys

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.KeyStore
import java.security.MessageDigest
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class MainActivity : FlutterActivity() {
    private val recoveryExecutor = Executors.newSingleThreadExecutor()
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "akys/recovery").setMethodCallHandler { call, result ->
            if (call.method !in listOf("read", "write", "delete")) {
                result.notImplemented()
            } else {
                recoveryExecutor.execute {
                    try {
                        val owner = call.argument<String>("owner") ?: error("Owner required")
                        require(owner.isNotEmpty() && owner.length <= 256)
                        val digest = MessageDigest.getInstance("SHA-256").digest(owner.toByteArray(Charsets.UTF_8))
                            .joinToString("") { "%02x".format(it) }
                        val alias = "akys.recovery.$digest"
                        // noBackupFilesDir excludes ciphertext from Android backup/restore.
                        val file = File(noBackupFilesDir, alias)
                        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
                        val answer: String? = when (call.method) {
                            "delete" -> {
                                if (file.exists() && !file.delete()) error("Cannot delete recovery")
                                keyStore.deleteEntry(alias)
                                null
                            }
                            "read" -> if (!file.exists()) null else {
                                val key = keyStore.getKey(alias, null) as? SecretKey ?: error("Recovery key unavailable")
                                val bytes = file.readBytes()
                                require(bytes.size >= 28)
                                val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                                cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
                                cipher.updateAAD(digest.toByteArray(Charsets.UTF_8))
                                String(cipher.doFinal(bytes.copyOfRange(12, bytes.size)), Charsets.UTF_8)
                            }
                            else -> {
                                val bytes = (call.argument<String>("plaintext") ?: error("Payload required")).toByteArray(Charsets.UTF_8)
                                require(bytes.size <= 2500000)
                                val key = (keyStore.getKey(alias, null) as? SecretKey) ?: KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").run {
                                    init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                                        .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                                        .setKeySize(256).build())
                                    generateKey()
                                }
                                val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                                cipher.init(Cipher.ENCRYPT_MODE, key)
                                cipher.updateAAD(digest.toByteArray(Charsets.UTF_8))
                                val encrypted = cipher.iv + cipher.doFinal(bytes)
                                val temporary = File(noBackupFilesDir, "$alias.tmp")
                                temporary.outputStream().use { it.write(encrypted); it.fd.sync() }
                                if (!temporary.renameTo(file)) error("Atomic recovery write failed")
                                null
                            }
                        }
                        runOnUiThread { result.success(answer) }
                    } catch (_: Exception) {
                        // Never disclose payload or key material in platform errors.
                        runOnUiThread { result.error("RECOVERY_UNAVAILABLE", "Şifreli yerel kurtarma tamamlanamadı.", null) }
                    }
                }
            }
        }
    }
    override fun onDestroy() {
        recoveryExecutor.shutdown()
        super.onDestroy()
    }
}
