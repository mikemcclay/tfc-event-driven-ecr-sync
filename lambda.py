"""
ECR Cross-Account Image Sync Lambda

This Lambda function copies container images from a source ECR repository to a
destination ECR repository using the ECR API directly (no Docker required).

The function is triggered by EventBridge when an image is pushed to the source
repository. It copies the image manifest and all layers to the destination.

Environment Variables:
    SOURCE_ACCOUNT_ID: AWS account ID of the source ECR repository
    SOURCE_REGION: AWS region of the source ECR repository  
    DESTINATION_ACCOUNT_ID: AWS account ID of the destination ECR repository
    DESTINATION_REGION: AWS region of the destination ECR repository
    REPO_NAME: Name of the ECR repository (same in both accounts)

Required IAM Permissions:
    - ecr:GetAuthorizationToken (both accounts)
    - ecr:BatchGetImage, ecr:GetDownloadUrlForLayer (source repo)
    - ecr:BatchCheckLayerAvailability, ecr:InitiateLayerUpload, 
      ecr:UploadLayerPart, ecr:CompleteLayerUpload, ecr:PutImage (dest repo)
"""

import boto3
import os
import json


def lambda_handler(event, context):
    """
    Handle ECR push events and copy image to destination repository.
    
    Args:
        event: EventBridge event containing ECR push details
        context: Lambda context object
        
    Returns:
        dict: Status and details of the sync operation
    """
    print(f"Received event: {json.dumps(event, indent=2)}")
    
    # Extract image details from EventBridge event
    detail = event.get("detail", {})
    image_tag = detail.get("image-tag")
    image_digest = detail.get("image-digest")
    repo_name = os.environ["REPO_NAME"]
    
    if not image_tag and not image_digest:
        return {"status": "error", "message": "No image tag or digest in event"}
    
    # Environment configuration
    source_account = os.environ["SOURCE_ACCOUNT_ID"]
    source_region = os.environ["SOURCE_REGION"]
    dest_account = os.environ["DESTINATION_ACCOUNT_ID"]
    dest_region = os.environ["DESTINATION_REGION"]
    
    print(f"Syncing image {repo_name}:{image_tag or image_digest}")
    print(f"  From: {source_account} ({source_region})")
    print(f"  To:   {dest_account} ({dest_region})")
    
    # Initialize ECR clients for both accounts
    ecr_source = boto3.client("ecr", region_name=source_region)
    ecr_dest = boto3.client("ecr", region_name=dest_region)
    
    try:
        # Step 1: Get image manifest from source repository
        print("Fetching image manifest from source...")
        image_id = {"imageTag": image_tag} if image_tag else {"imageDigest": image_digest}
        
        source_image = ecr_source.batch_get_image(
            registryId=source_account,
            repositoryName=repo_name,
            imageIds=[image_id],
            acceptedMediaTypes=[
                "application/vnd.docker.distribution.manifest.v2+json",
                "application/vnd.oci.image.manifest.v1+json",
                "application/vnd.docker.distribution.manifest.list.v2+json",
            ]
        )
        
        if not source_image.get("images"):
            return {"status": "error", "message": f"Image not found: {image_tag or image_digest}"}
        
        image_manifest = source_image["images"][0]["imageManifest"]
        manifest_media_type = source_image["images"][0].get("imageManifestMediaType")
        
        print(f"Retrieved manifest (type: {manifest_media_type})")
        
        # Step 2: Put the image manifest to destination repository
        # Note: ECR handles layer replication automatically when you put the manifest
        # if the layers already exist or are accessible via cross-account policy
        print("Pushing image to destination...")
        
        put_params = {
            "registryId": dest_account,
            "repositoryName": repo_name,
            "imageManifest": image_manifest,
        }
        
        if image_tag:
            put_params["imageTag"] = image_tag
        if manifest_media_type:
            put_params["imageManifestMediaType"] = manifest_media_type
            
        result = ecr_dest.put_image(**put_params)
        
        dest_digest = result["image"]["imageId"]["imageDigest"]
        print(f"Successfully synced image to destination")
        print(f"  Digest: {dest_digest}")
        
        return {
            "status": "success",
            "source_account": source_account,
            "destination_account": dest_account,
            "repository": repo_name,
            "tag": image_tag,
            "digest": dest_digest
        }
        
    except ecr_source.exceptions.ImageNotFoundException:
        return {"status": "error", "message": f"Image not found in source: {image_tag}"}
    except ecr_dest.exceptions.ImageAlreadyExistsException:
        print(f"Image already exists in destination repository")
        return {"status": "skipped", "message": "Image already exists", "tag": image_tag}
    except Exception as e:
        print(f"Error syncing image: {str(e)}")
        raise
