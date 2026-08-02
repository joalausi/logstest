apiVersion: batch/v1
kind: Job
metadata:
  name: __JOB_NAME__
  namespace: ci-cd
  labels:
    app.kubernetes.io/name: trivy
    app.kubernetes.io/part-of: cluster-chronicles
    cluster-chronicles/build: "__TAG__"
spec:
  backoffLimit: 1
  ttlSecondsAfterFinished: 600
  template:
    metadata:
      labels:
        app.kubernetes.io/name: trivy
        app.kubernetes.io/part-of: cluster-chronicles
    spec:
      restartPolicy: Never
      automountServiceAccountToken: false
      securityContext:
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: trivy
          image: aquasec/trivy:0.66.0
          args:
            - image
            - --exit-code=1
            - --severity=CRITICAL
            - --ignore-unfixed
            - --insecure
            - --no-progress
            - __REGISTRY__/cluster-chronicles-__COMPONENT__:__TAG__
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: "1"
              memory: 1Gi
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
          volumeMounts:
            - name: cache
              mountPath: /root/.cache
      volumes:
        - name: cache
          emptyDir: {}
