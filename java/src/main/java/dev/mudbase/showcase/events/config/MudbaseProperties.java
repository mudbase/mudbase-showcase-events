package dev.mudbase.showcase.events.config;

import jakarta.annotation.PostConstruct;
import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Every ID this app needs to talk to a provisioned Mudbase project. See java/.env.example for the
 * full list and where each value comes from - the same three collections (events/bookings/
 * activity) documented in ../web/plan/build-plan.md, no single-shared-parent-document quirk like
 * the sibling Kanban port's {@code boardId} needs (every {@code eventId}/{@code userId}/{@code
 * organizerId} field here is always a real Mudbase-issued ObjectId already - the signed-in user's
 * session id, or another document's real {@code _id}).
 */
@ConfigurationProperties(prefix = "mudbase")
public class MudbaseProperties {

  private String baseUrl;
  private String projectId;
  private String eventsCollectionId;
  private String bookingsCollectionId;
  private String activityCollectionId;

  @PostConstruct
  void validate() {
    requireNonBlank(projectId, "mudbase.project-id (MUDBASE_PROJECT_ID)");
    requireNonBlank(eventsCollectionId, "mudbase.events-collection-id (MUDBASE_EVENTS_COLLECTION_ID)");
    requireNonBlank(bookingsCollectionId, "mudbase.bookings-collection-id (MUDBASE_BOOKINGS_COLLECTION_ID)");
    requireNonBlank(activityCollectionId, "mudbase.activity-collection-id (MUDBASE_ACTIVITY_COLLECTION_ID)");
  }

  private static void requireNonBlank(String value, String name) {
    if (value == null || value.isBlank()) {
      throw new IllegalStateException("Missing required configuration value: " + name);
    }
  }

  public String getBaseUrl() {
    return baseUrl;
  }

  public void setBaseUrl(String baseUrl) {
    this.baseUrl = baseUrl;
  }

  public String getProjectId() {
    return projectId;
  }

  public void setProjectId(String projectId) {
    this.projectId = projectId;
  }

  public String getEventsCollectionId() {
    return eventsCollectionId;
  }

  public void setEventsCollectionId(String eventsCollectionId) {
    this.eventsCollectionId = eventsCollectionId;
  }

  public String getBookingsCollectionId() {
    return bookingsCollectionId;
  }

  public void setBookingsCollectionId(String bookingsCollectionId) {
    this.bookingsCollectionId = bookingsCollectionId;
  }

  public String getActivityCollectionId() {
    return activityCollectionId;
  }

  public void setActivityCollectionId(String activityCollectionId) {
    this.activityCollectionId = activityCollectionId;
  }
}
