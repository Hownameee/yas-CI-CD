pipeline {
    agent any

    parameters {
        string(name: 'backoffice_bff', defaultValue: 'latest', description: 'Branch for backoffice-bff')
        string(name: 'backoffice_ui', defaultValue: 'latest', description: 'Branch for backoffice-ui')
        string(name: 'storefront_bff', defaultValue: 'latest', description: 'Branch for storefront-bff')
        string(name: 'storefront_ui', defaultValue: 'latest', description: 'Branch for storefront-ui')
        string(name: 'cart', defaultValue: 'latest', description: 'Branch for cart')
        string(name: 'customer', defaultValue: 'latest', description: 'Branch for customer')
        string(name: 'inventory', defaultValue: 'latest', description: 'Branch for inventory')
        string(name: 'location', defaultValue: 'latest', description: 'Branch for location')
        string(name: 'media', defaultValue: 'latest', description: 'Branch for media')
        string(name: 'order', defaultValue: 'latest', description: 'Branch for order')
        string(name: 'payment', defaultValue: 'latest', description: 'Branch for payment')
        string(name: 'product', defaultValue: 'latest', description: 'Branch for product')
        string(name: 'promotion', defaultValue: 'latest', description: 'Branch for promotion')
        string(name: 'rating', defaultValue: 'latest', description: 'Branch for rating')
        string(name: 'search', defaultValue: 'latest', description: 'Branch for search')
        string(name: 'tax', defaultValue: 'latest', description: 'Branch for tax')
        string(name: 'recommendation', defaultValue: 'latest', description: 'Branch for recommendation')
        string(name: 'webhook', defaultValue: 'latest', description: 'Branch for webhook')
        string(name: 'sampledata', defaultValue: 'latest', description: 'Branch for sampledata')
    }

    environment {
        DOCKER_REGISTRY = 'hownamee'
        NAMESPACE = 'yas-CD'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scmGit(
                    branches: [[name: 'main']],
                    userRemoteConfigs: [[url: 'https://github.com/Hownameee/yas-CI-CD.git']]
                )
            }
        }

        stage('Initialize') {
            steps {
                script {
                    // Get Domain from cluster-config.yaml
                    def domainOutput = sh(script: "yq -r '.domain' k8s/deploy/cluster-config.yaml", returnStdout: true).trim()
                    env.DOMAIN = domainOutput ?: 'yas.local'
                    
                    // Get Node IP
                    def nodeIp = sh(script: "kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type==\"InternalIP\")].address}'", returnStdout: true).trim()
                    env.NODE_IP = nodeIp
                }
            }
        }

        stage('Deploy Services') {
            steps {
                script {
                    def services = [
                        'backoffice-bff', 'backoffice-ui', 'storefront-bff', 'storefront-ui',
                        'cart', 'customer', 'inventory', 'location', 'media', 'order', 
                        'payment', 'product', 'promotion', 'rating', 'search', 'tax', 
                        'recommendation', 'webhook', 'sampledata'
                    ]

                    for (service in services) {
                        // Normalize parameter name (replace - with _)
                        def paramName = service.replace('-', '_')
                        def branch = params."${paramName}" ?: 'latest'
                        def tag = branch

                        if (tag != 'latest') {
                            echo "Fetching latest commit ID for branch ${tag} of service ${service}"
                            // Assuming all code is in the same repo, we get the HEAD of the branch
                            tag = sh(script: "git ls-remote origin ${tag} | cut -f1", returnStdout: true).trim()
                            if (!tag) {
                                error "Could not find branch ${tag} on origin"
                            }
                        }

                        echo "DEBUG: Deploying ${service} with tag: ${tag} from branch: ${branch}"

                        /*
                        def chartPath = "k8s/charts/${service}"
                        def imageTagKey = service.contains('-ui') ? 'ui.image.tag' : 'backend.image.tag'
                        def serviceTypeKey = service.contains('-ui') ? 'ui.service.type' : 'backend.service.type'
                        def ingressEnabledKey = service.contains('-ui') ? 'ui.ingress.enabled' : 'backend.ingress.enabled'

                        sh """
                            cd ${chartPath}
                            helm dependency build .
                            helm upgrade --install ${service} . \
                                --namespace ${env.NAMESPACE} --create-namespace \
                                --set ${imageTagKey}=${tag} \
                                --set ${serviceTypeKey}=NodePort \
                                --set ${ingressEnabledKey}=false
                        """
                        */
                    }
                }
            }
        }

        /*
        stage('Access Information') {
            steps {
                script {
                    echo "=========================================================="
                    echo "DEPLOYMENT COMPLETE"
                    echo "=========================================================="
                    echo "Worker Node IP: ${env.NODE_IP}"
                    echo "Please add the following entries to your /etc/hosts file:"
                    echo "${env.NODE_IP}  backoffice.${env.DOMAIN} storefront.${env.DOMAIN} api.${env.DOMAIN}"
                    echo "----------------------------------------------------------"
                    echo "Access your services directly via NodePort:"
                    
                    def services = [
                        'backoffice-bff', 'backoffice-ui', 'storefront-bff', 'storefront-ui',
                        'cart', 'customer', 'inventory', 'location', 'media', 'order', 
                        'payment', 'product', 'promotion', 'rating', 'search', 'tax', 
                        'recommendation', 'webhook', 'sampledata'
                    ]

                    for (service in services) {
                        def nodePort = sh(script: "kubectl get svc ${service} -n ${env.NAMESPACE} -o jsonpath='{.spec.ports[0].nodePort}'", returnStdout: true).trim()
                        def subDomain = ""
                        if (service == 'backoffice-ui') subDomain = "backoffice."
                        else if (service == 'storefront-ui') subDomain = "storefront."
                        else if (service == 'swagger-ui') subDomain = "api."
                        else subDomain = "${service}."

                        echo "${service.padRight(20)}: http://${subDomain}${env.DOMAIN}:${nodePort}"
                    }
                    echo "=========================================================="
                }
            }
        }
        */
    }
}
