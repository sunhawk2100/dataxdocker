FROM anapsix/alpine-java:jdk8
MAINTAINER Levon.yao <levon.yao@linksame.cn>, Linksame Team


# Patch APK Mirror to LINKSAME
RUN echo "http://mirrors.ustc.edu.cn/alpine/v3.3/main/" > /etc/apk/repositories


ENV PATH /usr/local/bin:$PATH
ENV LANG C.UTF-8
RUN apk add --no-cache ca-certificates

ENV GPG_KEY 8417157EDBE73D9EAC1E539B126EB563A74B06BF
ENV PYTHON_VERSION 2.6.9

# if this is called "PIP_VERSION", pip explodes with "ValueError: invalid truth value '<VERSION>'"
ENV PYTHON_PIP_VERSION 9.0.1

COPY python-2.6-internal-expat.patch /python-2.6-internal-expat.patch
COPY python-2.6-posix-module.patch /python-2.6-posix-module.patch

RUN set -ex \
    && apk add --no-cache --virtual .fetch-deps \
        openssl \
        gnupg \
        tar \
        xz \
    \
    && wget -O python.tar.xz "https://www.python.org/ftp/python/${PYTHON_VERSION%%[a-z]*}/Python-$PYTHON_VERSION.tar.xz" \
    && wget -O python.tar.xz.asc "https://www.python.org/ftp/python/${PYTHON_VERSION%%[a-z]*}/Python-$PYTHON_VERSION.tar.xz.asc" \
    && export GNUPGHOME="$(mktemp -d)" \
    && gpg --keyserver ha.pool.sks-keyservers.net --recv-keys "$GPG_KEY" \
    && gpg --batch --verify python.tar.xz.asc python.tar.xz \
    && rm -r "$GNUPGHOME" python.tar.xz.asc \
    && mkdir -p /usr/src/python \
    && tar -xJC /usr/src/python --strip-components=1 -f python.tar.xz \
    && rm python.tar.xz \
    \
    && apk add --no-cache --virtual .build-deps  \
        gcc \
        libc-dev \
        linux-headers \
        make \
        openssl \
        readline-dev \
        tcl-dev \
        tk \
        tk-dev \
        expat-dev \
        openssl-dev \
        zlib-dev \
        ncurses-dev \
        bzip2-dev \
        gdbm-dev \
        sqlite-dev \
        libffi-dev \
# add build deps before removing fetch deps in case there's overlap
    && apk del .fetch-deps \
    \
    && cd /usr/src/python \
    && mv /python-2.6-internal-expat.patch python-2.6-internal-expat.patch \
    && mv /python-2.6-posix-module.patch python-2.6-posix-module.patch \
    && ls -la \
    && patch -p1 < python-2.6-internal-expat.patch \
    && patch -p1 < python-2.6-posix-module.patch \
    && ./configure --prefix=/usr \
    --enable-shared \
    --with-threads \
    --with-system-ffi \
    --enable-unicode=ucs4 \
    && make -j$(getconf _NPROCESSORS_ONLN) \
    && make install \
    && ln -s /usr/bin/python2.6 /usr/bin/python2 \
    \
        && wget -O /tmp/get-pip.py 'https://bootstrap.pypa.io/get-pip.py' \
        && python2 /tmp/get-pip.py "pip==$PYTHON_PIP_VERSION" \
        && rm /tmp/get-pip.py \
# we use "--force-reinstall" for the case where the version of pip we're trying to install is the same as the version bundled with Python
# ("Requirement already up-to-date: pip==8.1.2 in /usr/local/lib/python3.6/site-packages")
# https://github.com/docker-library/python/pull/143#issuecomment-241032683
    && pip install --no-cache-dir --upgrade --force-reinstall "pip==$PYTHON_PIP_VERSION" \
# then we use "pip list" to ensure we don't have more than one pip version installed
# https://github.com/docker-library/python/pull/100
    && [ "$(pip list |tac|tac| awk -F '[ ()]+' '$1 == "pip" { print $2; exit }')" = "$PYTHON_PIP_VERSION" ] \
    \
    && find /usr/local -depth \
        \( \
            \( -type d -a -name test -o -name tests \) \
            -o \
            \( -type f -a -name '*.pyc' -o -name '*.pyo' \) \
        \) -exec rm -rf '{}' + \
    && runDeps="$( \
        scanelf --needed --nobanner --recursive /usr/local \
            | awk '{ gsub(/,/, "\nso:", $2); print "so:" $2 }' \
            | sort -u \
            | xargs -r apk info --installed \
            | sort -u \
    )" \
    && apk add --virtual .python-rundeps $runDeps \
    && apk del .build-deps \
    && rm -rf /usr/src/python ~/.cache


  ENV MAVEN_HOME=/usr/share/maven
  RUN apk --no-cache add ca-certificates openssl &&  update-ca-certificates

  RUN cd /tmp \
     && wget https://archive.apache.org/dist/maven/maven-3/3.3.9/binaries/apache-maven-3.3.9-bin.tar.gz \
     && wget https://archive.apache.org/dist/maven/maven-3/3.3.9/binaries/apache-maven-3.3.9-bin.tar.gz.sha1 \
     && echo -e "$(cat apache-maven-3.3.9-bin.tar.gz.sha1)  apache-maven-3.3.9-bin.tar.gz" | sha1sum -c - \
     && tar zxf apache-maven-3.3.9-bin.tar.gz \
     && rm -rf apache-maven-3.3.9-bin.tar.gz \
     && rm -rf *.sha1 \
     && mv ./apache-maven-3.3.9 /usr/share/maven \
     && ln -s /usr/share/maven/bin/mvn /usr/bin/mvn

RUN apk add --update openssl && \
    rm -rf /var/cache/apk/* /tmp/*

# set version info for desired tomcat version
ENV TC_MAJOR 8
ENV TC_VERSION 8.0.44

# calculate download url
ENV TC_URL https://www.apache.org/dist/tomcat/tomcat-$TC_MAJOR/v$TC_VERSION/bin/apache-tomcat-$TC_VERSION.tar.gz

# download and verify tomcat
WORKDIR /opt
RUN wget $TC_URL && \
	wget $TC_URL.sha1 && \
	sha1sum -cw apache-tomcat-$TC_VERSION.tar.gz.sha1

# install tomcat to /opt/apache-tomcat
RUN	tar -xzf apache-tomcat-$TC_VERSION.tar.gz && \
	mv apache-tomcat-$TC_VERSION apache-tomcat

# remove unnecessary components
RUN	rm -f apache-tomcat/bin/*.bat && \
	rm -rf apache-tomcat/webapps/docs && \
	rm -rf apache-tomcat/webapps/examples && \
	rm -rf apache-tomcat/webapps/manager && \
	rm -rf apache-tomcat/webapps/host-manager && \
	rm -f apache-tomcat-$TC_VERSION.*

#improve tomcat startup performance by setting non blocking random generator
RUN echo "CATALINA_OPTS=-Djava.security.egd=file:/dev/./urandom" > apache-tomcat/bin/setenv.sh && \
	chmod a+x apache-tomcat/bin/setenv.sh

WORKDIR /opt/apache-tomcat

# add volume for webapps folder
VOLUME /opt/apache-tomcat/webapps

# expose http and jmx ports
EXPOSE 8080 

# run tomcat by default
CMD ["/opt/apache-tomcat/bin/catalina.sh", "run"]
