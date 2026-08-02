apiVersion: batch/v1
kind: Job
metadata:
  name: __JOB_NAME__
  namespace: ci-cd
  labels:
    app.kubernetes.io/name: kaniko
    app.kubernetes.io/part-of: cluster-chronicles
    cluster-chronicles/build: "__TAG__"
spec:
  backoffLimit: 1
  ttlSecondsAfterFinished: 600
  template:
    metadata:
      labels:
        app.kubernetes.io/name: kaniko
        app.kubernetes.io/part-of: cluster-chronicles
    spec:
      restartPolicy: Never
      automountServiceAccountToken: false
      securityContext:
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: kaniko
          image: gcr.io/kaniko-project/executor:v1.23.2-debug
          args:
            - --context=dir:///workspace/workspace/cluster-chronicles/app/__COMPONENT__
            - --dockerfile=/workspace/workspace/cluster-chronicles/app/__COMPONENT__/__DOCKERFILE__
            - --destination=__REGISTRY__/cluster-chronicles-__COMPONENT__:__TAG__
            - --destination=__REGISTRY__/cluster-chronicles-__COMPONENT__:latest
            - --insecure
            - --skip-tls-verify-registry=__REGISTRY__
            - --cache=true
            - --cache-repo=__REGISTRY__/cluster-chronicles-__COMPONENT__-cache
            - --snapshot-mode=redo
          resources:
            requests:
              cpu: 200m
              memory: 256Mi
            limits:
              cpu: "2"
              memory: 2Gi
          securityContext:
            allowPrivilegeEscalation: false
          volumeMounts:
            - name: jenkins-home
              mountPath: /workspace
              readOnly: true
            - name: kaniko-tmp
              mountPath: /kaniko/.docker
      volumes:
        - name: jenkins-home
          persistentVolumeClaim:
            claimName: jenkins-home
        - name: kaniko-tmp
          emptyDir: {}
