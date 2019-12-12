pipeline {

   parameters {
    choice(name: 'action', choices: 'create\ndestroy', description: 'Create/update or destroy the eks cluster.')
    string(name: 'cluster', defaultValue : 'alsac-eks', description: "EKS cluster name;eg demo creates cluster named eks-demo.")
    string(name: 'vpc_name', defaultValue : '', description: "k8s worker node instance type.")
    string(name: 'instance_type', defaultValue : 't2.micro', description: "k8s worker node instance type.")
    string(name: 'credential', defaultValue : 'awscredentials', description: "Jenkins credential that provides the AWS access key and secret.")
    string(name: 'region', defaultValue : 'us-east-1', description: "AWS region.")
  }

  options {
    disableConcurrentBuilds()
    timeout(time: 1, unit: 'HOURS')
    ansiColor('xterm')
  }

  agent {
    node {
      label 'master'
    }  
  }
   
  stages {

    stage('Setup') {
      steps {
        script {
          currentBuild.displayName = "#" + env.BUILD_NUMBER + " " + params.action + " eks-" + params.cluster
          plan = params.cluster + '.plan'
        }
      }
    }

    stage('TF Plan') {
      when {
        expression { params.action == 'create' }
      }
      steps {
        script {
          withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', 
            credentialsId: params.credential, 
            accessKeyVariable: 'AWS_ACCESS_KEY_ID',  
            secretKeyVariable: 'AWS_SECRET_ACCESS_KEY']]) {

            sh """
              terraform init
              terraform workspace new ${params.cluster} || true
              terraform workspace select ${params.cluster}
              terraform plan \
                -var cluster-name=${params.cluster} \
                -var inst-type=${params.instance_type} \
                -out ${plan}
            """
          }
        }
      }
    }

    stage('TF Apply') {
      when {
        expression { params.action == 'create' }
      }
      steps {
        script {
          input "Create/update Terraform stack eks-${params.cluster} in aws?" 

          withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', 
            credentialsId: params.credential, 
            accessKeyVariable: 'AWS_ACCESS_KEY_ID',  
            secretKeyVariable: 'AWS_SECRET_ACCESS_KEY']]) {

            sh """
              terraform apply -input=false ${plan}
            """
          }
        }
      }
    }

    stage('TF Destroy') {
      when {
        expression { params.action == 'destroy' }
      }
      steps {
        script {
          input "Destroy Terraform stack eks-${params.cluster} in aws?" 

          withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', 
            credentialsId: params.credential, 
            accessKeyVariable: 'AWS_ACCESS_KEY_ID',  
            secretKeyVariable: 'AWS_SECRET_ACCESS_KEY']]) {

            sh """
              terraform workspace select ${params.cluster}
              terraform destroy -auto-approve
            """
          }
        }
      }
    }

  }

}
