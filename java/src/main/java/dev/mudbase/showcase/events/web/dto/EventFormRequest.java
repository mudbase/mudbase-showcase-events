package dev.mudbase.showcase.events.web.dto;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

/**
 * Shared shape for both "create event" and "edit event" forms - caps match the reference web
 * app's zod schema exactly (title 200, description 2000, location 200, capacity 1-100000).
 * {@code startsAt} carries the raw value an HTML `<input type="datetime-local">` submits
 * ("yyyy-MM-ddTHH:mm"); {@link dev.mudbase.showcase.events.support.Formatting#parseDateTimeLocalToIso}
 * converts it to a full ISO-8601 instant before it's sent to Mudbase.
 */
public class EventFormRequest {

  @NotBlank(message = "Title is required")
  @Size(max = 200, message = "Title is too long")
  private String title = "";

  @Size(max = 2000, message = "Description is too long")
  private String description = "";

  @NotBlank(message = "Date and time is required")
  private String startsAt = "";

  @NotBlank(message = "Location is required")
  @Size(max = 200, message = "Location is too long")
  private String location = "";

  @NotNull(message = "Capacity is required")
  @Min(value = 1, message = "Capacity must be at least 1")
  @Max(value = 100000, message = "Capacity is unrealistically large")
  private Integer capacity = 20;

  public String getTitle() {
    return title;
  }

  public void setTitle(String title) {
    this.title = title;
  }

  public String getDescription() {
    return description;
  }

  public void setDescription(String description) {
    this.description = description;
  }

  public String getStartsAt() {
    return startsAt;
  }

  public void setStartsAt(String startsAt) {
    this.startsAt = startsAt;
  }

  public String getLocation() {
    return location;
  }

  public void setLocation(String location) {
    this.location = location;
  }

  public Integer getCapacity() {
    return capacity;
  }

  public void setCapacity(Integer capacity) {
    this.capacity = capacity;
  }
}
