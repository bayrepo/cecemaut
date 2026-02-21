FROM almalinux:9

RUN yum -y install dnf-plugins-core && \
    dnf config-manager --set-enabled crb

# Install build tools and dependencies for RVM / Ruby
RUN yum -y update && \
    yum -y  --allowerasing install \
        curl git gnupg2 \
        gcc gcc-c++ patch \
        readline-devel zlib-devel libyaml-devel libffi-devel openssl-devel ruby ruby-devel which procps-ng && \
    yum clean all

# Install RVM and Ruby 3.3.0
RUN gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys \
        409B6B1796C275462A1703113804BB82D39DC0E3 \
        7D2BAF1CF37B13E2069D6956105BD0E739499BDB && \
    curl -sSL https://get.rvm.io | bash -s stable --ruby=3.3.0 && \
    echo 'source /etc/profile.d/rvm.sh' >> /etc/profile && \
    /bin/bash -lc "source /etc/profile.d/rvm.sh && gem install bundler"

# Make RVM binaries available
ENV PATH="/usr/local/rvm/bin:${PATH}"

# Set Ruby 3.3.0 as the default version
RUN /bin/bash -lc "source /etc/profile.d/rvm.sh && rvm use 3.3.0 --default"

# Create application user
RUN useradd -m certuser

# Create project directory and set working directory
WORKDIR /opt/cert/certcenter

# Copy only the specified directories and files
COPY ca ./ca/
COPY classes ./classes/
COPY db ./db/
COPY docs ./docs/
COPY locale ./locale/
COPY logs ./logs/
COPY locks ./locks/
COPY migration ./migration/
COPY models ./models/
COPY public ./public/
COPY utils ./utils/
COPY views ./views/
COPY .bundle ./.bundle/
COPY app.rb Gemfile Gemfile.lock ./

# Make the CA directory a bind mount point
VOLUME /opt/cert/certcenter/ca
VOLUME /opt/cert/certcenter/logs

# Prepare the application
RUN /bin/bash -lc "source /etc/profile.d/rvm.sh && chmod +x ./utils/make_app_keys.sh" && \
    /bin/bash -lc "source /etc/profile.d/rvm.sh && ./utils/make_app_keys.sh ." && \
    /bin/bash -lc "source /etc/profile.d/rvm.sh && bundle install" && \
    /bin/bash -lc "source /etc/profile.d/rvm.sh && bundle exec sequel -m migration sqlite://db/base.sqlite"

EXPOSE 4567

CMD ["bash", "-lc", "source /etc/profile.d/rvm.sh && bundle exec ruby app.rb"]
