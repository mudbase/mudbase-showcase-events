package dev.mudbase.showcase.events.web;

import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.InterceptorRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

/** Registers {@link AuthGateInterceptor} against every route except the login page and static assets. */
@Configuration
public class WebConfig implements WebMvcConfigurer {

  private final AuthGateInterceptor authGateInterceptor;

  public WebConfig(AuthGateInterceptor authGateInterceptor) {
    this.authGateInterceptor = authGateInterceptor;
  }

  @Override
  public void addInterceptors(InterceptorRegistry registry) {
    registry.addInterceptor(authGateInterceptor).excludePathPatterns("/login", "/logout", "/css/**", "/error", "/favicon.ico");
  }
}
