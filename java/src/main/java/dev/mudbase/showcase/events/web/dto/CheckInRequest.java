package dev.mudbase.showcase.events.web.dto;

import jakarta.validation.constraints.NotBlank;

/** The organizer's check-in form: a single pasted/typed {@code qrToken}. */
public class CheckInRequest {

  @NotBlank(message = "Paste or type the scanned code")
  private String qrToken = "";

  public String getQrToken() {
    return qrToken;
  }

  public void setQrToken(String qrToken) {
    this.qrToken = qrToken;
  }
}
