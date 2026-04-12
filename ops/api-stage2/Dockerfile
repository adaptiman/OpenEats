FROM adaptiman/openeats-api@sha256:0708a8b232dbd11a720e07bc171b663eb1038cb5ea9249a2c1f695d71c61e8c2

# Stage 2 conservative backend dependency refresh on Python 3.6 base.
# Keep DRF/router API unchanged to avoid code-level refactors in this stage.
RUN pip install --no-cache-dir \
    'Django==2.2.28' \
    'mysqlclient==1.4.6' \
    'Pillow==6.2.2' \
    'requests==2.27.1'
