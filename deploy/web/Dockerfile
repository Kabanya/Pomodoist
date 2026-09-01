FROM getsentry/sentry-cli:2.57.0@sha256:f2c99e93ccdaf7b934ba804946ea90405eb2b1b9fdb3aa42bcbb501641c6f01f AS sentry-cli

FROM ghcr.io/cirruslabs/flutter:3.41.9@sha256:c6fed8fee02ca8fdb1b8dc128df99f6e29b7305847b80f4b0c1e3f638e7637a8 AS builder

USER root
WORKDIR /src
COPY .fvmrc ./
RUN flutter_version="$(jq -r .flutter .fvmrc)" \
    && git -C "$FLUTTER_HOME" fetch --depth 1 origin "refs/tags/$flutter_version" \
    && git -C "$FLUTTER_HOME" checkout --detach FETCH_HEAD
ARG POMODOIST_BILLING_CHANNEL
RUN [ "$POMODOIST_BILLING_CHANNEL" = stripe ] \
    || (echo 'POMODOIST_BILLING_CHANNEL must be stripe' >&2; exit 1)
COPY pubspec.yaml pubspec.lock l10n.yaml ./
COPY lib/l10n/ ./lib/l10n/
RUN --mount=type=cache,target=/root/.pub-cache \
    flutter pub get
COPY lib/ ./lib/
COPY web/ ./web/
COPY assets/ ./assets/
COPY tool/prepare_sentry_sourcemaps.dart ./tool/prepare_sentry_sourcemaps.dart
RUN --mount=type=cache,target=/root/.pub-cache \
    flutter build web --release --source-maps --pwa-strategy=none \
      --dart-define=POMODOIST_BILLING_CHANNEL="$POMODOIST_BILLING_CHANNEL" \
    && dart run tool/prepare_sentry_sourcemaps.dart build/web/main.dart.js.map /src \
    && rm -f \
      build/web/flutter_service_worker.js \
      build/web/.last_build_id \
      build/web/config.js \
      build/web/GoogleOAuth.env \
      build/web/GoogleOAuth.env.example \
      build/web/drift_worker.dart

ARG RELEASE_SHA
RUN printf '%s' "$RELEASE_SHA" | grep -Eq '^[0-9a-f]{40}$' \
    && printf '%s\n' "$RELEASE_SHA" > /image-release

FROM sentry-cli AS symbolicated
WORKDIR /src
COPY --from=builder /src/build/web/ ./build/web/
COPY --from=builder /image-release /image-release
RUN sentry-cli sourcemaps inject \
    build/web/main.dart.js \
    build/web/main.dart.js.map

FROM scratch AS sentry-source-maps
COPY --from=symbolicated /src/build/web/main.dart.js /artifacts/main.dart.js
COPY --from=symbolicated /src/build/web/main.dart.js.map /artifacts/main.dart.js.map
COPY --from=symbolicated /image-release /release

FROM symbolicated AS runtime-assets
RUN find build/web -type f -name '*.map' -delete

FROM ghcr.io/jqlang/jq:1.8.1@sha256:4f34c6d23f4b1372ac789752cc955dc67c2ae177eb1b5860b75cdc5091ce6f91 AS jq

FROM nginx:1.28.0-bookworm@sha256:552e7481ca93ffccd046aa658dbbed22caefbc09c66fa7cd247cbb90b8a5c609

RUN rm -f /etc/nginx/conf.d/default.conf
COPY --from=jq /jq /usr/local/bin/jq
COPY --from=runtime-assets --chown=nginx:nginx /src/build/web/ /usr/share/nginx/html/
COPY --chown=nginx:nginx telegram-mini-app/ /usr/share/nginx/html/telegram/
COPY --from=builder --chown=nginx:nginx /src/web/.well-known/apple-app-site-association /usr/share/nginx/html/.well-known/apple-app-site-association
COPY --from=symbolicated --chown=nginx:nginx /image-release /usr/share/nginx/image-release
COPY deploy/web/nginx.conf /etc/nginx/nginx.conf
COPY deploy/web/security-headers.conf.template /etc/nginx/pomodoist-security-headers.conf.template
COPY deploy/web/entrypoint.sh /usr/local/bin/pomodoist-entrypoint
RUN chown nginx:nginx /usr/share/nginx/html

USER nginx
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/pomodoist-entrypoint"]
CMD ["nginx", "-g", "daemon off;"]
