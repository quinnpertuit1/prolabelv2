ARG PYTHON_VERSION="3.6"
FROM python:${PYTHON_VERSION}-stretch AS builder

ARG NODE_VERSION="8.x"
RUN curl -sL "https://deb.nodesource.com/setup_${NODE_VERSION}" | bash - \
 && apt-get install --no-install-recommends -y \
      nodejs

COPY tools/install-mssql.sh /prolabel/tools/install-mssql.sh
RUN /prolabel/tools/install-mssql.sh --dev

COPY app/server/static/package*.json /prolabel/app/server/static/
RUN cd /prolabel/app/server/static \
 && npm ci

COPY requirements.txt /
RUN pip install -r /requirements.txt \
 && pip wheel -r /requirements.txt -w /deps

COPY . /prolabel

WORKDIR /prolabel
RUN tools/ci.sh

FROM builder AS cleaner

RUN cd /prolabel/app/server/static \
 && SOURCE_MAP=False DEBUG=False npm run build \
 && rm -rf components pages node_modules .*rc package*.json webpack.config.js

RUN cd /prolabel \
 && python app/manage.py collectstatic --noinput

FROM python:${PYTHON_VERSION}-slim-stretch AS runtime

COPY --from=builder /prolabel/tools/install-mssql.sh /prolabel/tools/install-mssql.sh
RUN /prolabel/tools/install-mssql.sh

RUN useradd -ms /bin/sh prolabel

COPY --from=builder /deps /deps
RUN pip install --no-cache-dir /deps/*.whl

COPY --from=cleaner --chown=prolabel:prolabel /prolabel /prolabel

ENV DEBUG="True"
ENV SECRET_KEY="change-me-in-production"
ENV PORT="8000"
ENV WORKERS="2"
ENV GOOGLE_TRACKING_ID=""
ENV AZURE_APPINSIGHTS_IKEY=""

USER prolabel
WORKDIR /prolabel
EXPOSE ${PORT}

CMD ["/prolabel/tools/run.sh"]
