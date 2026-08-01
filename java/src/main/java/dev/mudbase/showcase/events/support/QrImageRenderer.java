package dev.mudbase.showcase.events.support;

import com.google.zxing.BarcodeFormat;
import com.google.zxing.EncodeHintType;
import com.google.zxing.MultiFormatWriter;
import com.google.zxing.WriterException;
import com.google.zxing.client.j2se.MatrixToImageWriter;
import com.google.zxing.common.BitMatrix;
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.util.Base64;
import java.util.EnumMap;
import java.util.Map;

/**
 * Renders a booking's {@code qrToken} as a real, scannable QR code image - the server-rendered
 * equivalent of the reference web app's {@code <QRCodeSVG>} component (../web's `qrcode.react`
 * dependency). Since this is a plain server-rendered Thymeleaf app with no client-side JS
 * rendering library, the PNG is generated once per page render and inlined directly as a
 * {@code data:} URI - no extra route, no static file, no client-side dependency.
 */
public final class QrImageRenderer {

  private static final int DEFAULT_SIZE_PX = 160;

  private QrImageRenderer() {}

  /** Renders {@code content} as a PNG QR code and returns it as a `data:image/png;base64,...` URI ready for an `<img src>`. */
  public static String renderPngDataUri(String content) {
    return renderPngDataUri(content, DEFAULT_SIZE_PX);
  }

  public static String renderPngDataUri(String content, int sizePx) {
    try {
      Map<EncodeHintType, Object> hints = new EnumMap<>(EncodeHintType.class);
      hints.put(EncodeHintType.ERROR_CORRECTION, ErrorCorrectionLevel.M);
      hints.put(EncodeHintType.MARGIN, 1);
      BitMatrix matrix = new MultiFormatWriter().encode(content, BarcodeFormat.QR_CODE, sizePx, sizePx, hints);
      ByteArrayOutputStream out = new ByteArrayOutputStream();
      MatrixToImageWriter.writeToStream(matrix, "PNG", out);
      return "data:image/png;base64," + Base64.getEncoder().encodeToString(out.toByteArray());
    } catch (WriterException | IOException e) {
      throw new IllegalStateException("Could not render QR code image", e);
    }
  }
}
