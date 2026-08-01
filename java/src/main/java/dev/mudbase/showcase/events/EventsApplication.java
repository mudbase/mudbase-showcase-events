package dev.mudbase.showcase.events;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.ConfigurationPropertiesScan;

/**
 * Mudbase Showcase — Events: an event booking/ticketing app served entirely by Mudbase
 * (cloud.mudbase.dev) — auth, database, role-based access control, no custom backend of any kind.
 * This Spring Boot + Thymeleaf app is the Java reimplementation of the reference Next.js app at
 * ../web - same Mudbase project, same three collections (events/bookings/activity), same RBAC
 * matrix, capacity/waitlist-promotion algorithm, and QR check-in flow; see plan/build-plan.md for
 * what deliberately differs (server-rendered forms and a server-rendered QR image instead of
 * client-side rendering, and why).
 */
@SpringBootApplication
@ConfigurationPropertiesScan
public class EventsApplication {

  public static void main(String[] args) {
    SpringApplication.run(EventsApplication.class, args);
  }
}
