'''
Object Store Service
'''

from logging import basicConfig, getLogger, INFO

from boto3 import client
from botocore.exceptions import ClientError


class ObjectStore:
    '''
    Provide authentication and essential operations to object store.
    Use graceful error handling and logging without raising exceptions.
    - buckets: list, create and delete
    - folders: list, create and delete
    - objects: list, create, copy, retrieve and delete
    '''

    def __init__(self,
                 host: str = None,
                 port: int = None,
                 access: str = None,
                 secret: str = None,
                 region: str = None) -> None:

        basicConfig(
            level=INFO, # default logging level
            format='%(asctime)s | %(levelname)-8s | %(name)s.%(funcName)s | %(message)s',
            datefmt='%Y-%m-%d %H:%M:%S'
        )

        # getLogger('boto3').setLevel(WARNING) # set specific levels

        self.logger = getLogger(self.__class__.__name__)

        self.logger.info('host=%s port=%s access=%s secret=%s region=%s', host, port, access, secret, region)
        
        endpoint = f'{host}:{port}' if port else host # handles none checking for host and port
        verify = 'localhost' not in host if host else True # disables ssl verification for localhost
        
        self.client = client('s3', # simple storage service
                             endpoint_url=endpoint,
                             aws_access_key_id=access,
                             aws_secret_access_key=secret,
                             region_name=region,
                             verify=verify)

        self.region = region

    ########## BUCKETS ##########

    def list_buckets(self) -> list[str]:
        '''List all buckets'''
        try:
            response = self.client.list_buckets()
            buckets = [bucket['Name'] for bucket in response.get('Buckets', [])]
            return buckets
        except Exception as exception:
            self.logger.error('Fail to list buckets: %s', exception)
            return []


    def create_bucket(self, name: str) -> bool:
        '''Create a new bucket'''
        try:
            if self.region is None:
                self.client.create_bucket(Bucket=name)
            else:
                configuration = {'LocationConstraint': self.region}
                self.client.create_bucket(Bucket=name, CreateBucketConfiguration=configuration)
            return True
        except Exception as exception:
            self.logger.error('Fail to create bucket %s: %s', name, exception)
            return False


    def delete_bucket(self, name: str, force: bool = False) -> bool:
        '''Delete a bucket. If force=True, deletes all objects first'''
        try:
            if force: # list and delete all objects in the bucket
                paginator = self.client.get_paginator('list_objects_v2')
                pages = paginator.paginate(Bucket=name)
                for page in pages:
                    if 'Contents' in page:
                        objects = [{'Key': o['Key']} for o in page['Contents']]
                        if objects:
                            self.client.delete_objects(Bucket=name, Delete={'Objects': objects})
                
            self.client.delete_bucket(Bucket=name)
            return True
        except Exception as exception:
            self.logger.error('Fail to delete bucket %s: %s', name, exception)
            return False

    ########## FOLDERS ##########

    def list_folders(self, bucket: str, prefix: str = '') -> list[str]:
        '''List all folders in a bucket with the given prefix'''
        try:
            if prefix and not prefix.endswith('/'):
                prefix += '/' # ensure prefix ends with slash if it's not empty
            paginator = self.client.get_paginator('list_objects_v2')
            pages = paginator.paginate(Bucket=bucket, Prefix=prefix, Delimiter='/')
            folders = []
            for page in pages: # up to 1000 objects per page
                if 'CommonPrefixes' in page:
                    for common in page['CommonPrefixes']:
                        folders.append(common['Prefix'])
            return folders
        except Exception as exception:
            self.logger.error('Fail to list folders in bucket %s with prefix %s: %s', bucket, prefix, exception)
            return []


    def create_folder(self, bucket: str, prefix: str) -> bool:
        '''Create a new folder in a bucket'''
        try:
            if not prefix.endswith('/'):
                prefix += '/' # ensure prefix ends with slash
            self.client.put_object(Bucket=bucket, Key=prefix, Body='')
            return True
        except Exception as exception:
            self.logger.error('Fail to create folder %s in bucket %s: %s', prefix, bucket, exception)
            return False


    def delete_folder(self, bucket: str, prefix: str, force: bool = False) -> bool:
        '''Delete a folder in a bucket. If force=True, deletes all objects first'''
        try:
            if not prefix.endswith('/'):
                prefix += '/' # ensure prefix ends with slash
            if force: # list and delete all objects in the folder
                paginator = self.client.get_paginator('list_objects_v2')
                pages = paginator.paginate(Bucket=bucket, Prefix=prefix)
                for page in pages: # up to 1000 objects per page
                    if 'Contents' in page:
                        objects = [{'Key': o['Key']} for o in page['Contents']]
                        if objects:
                            self.client.delete_objects(Bucket=bucket, Delete={'Objects': objects})
            else: # delete only the folder object
                self.client.delete_object(Bucket=bucket, Key=prefix)
            return True
        except Exception as exception:
            self.logger.error('Fail to delete folder %s in bucket %s: %s', prefix, bucket, exception)
            return False

    ########## OBJECTS ##########

    def list_objects(self, bucket: str, prefix: str = '') -> list[str]:
        '''List all objects in a bucket with the given prefix'''
        try:
            paginator = self.client.get_paginator('list_objects_v2')
            pages = paginator.paginate(Bucket=bucket, Prefix=prefix)
            objects = []
            for page in pages: # up to 1000 objects per page
                if 'Contents' in page:
                    objects.extend([c['Key'] for c in page['Contents']])
            return objects
        except Exception as exception:
            self.logger.error('Fail to list objects in bucket %s with prefix %s: %s', bucket, prefix, exception)
            return []


    def create_object(self, bucket: str, key: str, source: str, etag: str = None) -> bool:
        '''
        Create a new object in a bucket from a file source path.
        If etag is provided, only uploads if existing object's ETag matches.
        '''
        try:
            with open(source, 'rb') as file:
                body = file.read()            
                if etag:
                    self.client.put_object(Bucket=bucket, Key=key, Body=body, IfMatch=etag)
                else:
                    self.client.put_object(Bucket=bucket, Key=key, Body=body)
            return True
        except ClientError as error:
            code = error.response['Error']['Code']
            if code == 'PreconditionFailed':  # 412 - etag mismatch
                self.logger.error('ETag mismatch for object %s: expected %s', key, etag)
            elif code == '404':
                self.logger.error('Object %s does not exist, cannot verify ETag', key)
            else:
                self.logger.error('Error to create object %s in bucket %s: %s', key, bucket, error)
            return False
        except Exception as exception:
            self.logger.error('Fail to create object %s in bucket %s: %s', key, bucket, exception)
            return False


    def upload_object(self, bucket: str, key: str, source: str) -> bool:
        '''Upload a large file object in a bucket from a file source path'''
        try:
            with open(source, 'rb') as file: # read as binary and treat as stream
                self.client.upload_fileobj(Fileobj=file, Bucket=bucket, Key=key)
            return True
        except Exception as exception:
            self.logger.error('Fail to create object %s in bucket %s: %s', key, bucket, exception)
            return False


    def copy_object(self, source_bucket: str, source_key: str, target_bucket: str, target_key: str) -> bool:
        '''Copy an object from source to target'''
        try:
            source = {'Bucket': source_bucket, 'Key': source_key}
            self.client.copy(CopySource=source, Bucket=target_bucket, Key=target_key)
            return True
        except Exception as exception:
            self.logger.error('Fail to copy object %s/%s to %s/%s: %s',
                              source_bucket, source_key, target_bucket, target_key, exception)
            return False


    def move_object(self, source_bucket: str, source_key: str, target_bucket: str, target_key: str) -> bool:
        '''Move an object from source to target'''
        try:
            source = {'Bucket': source_bucket, 'Key': source_key}
            self.client.copy(CopySource=source, Bucket=target_bucket, Key=target_key)
            self.client.delete_object(Bucket=source_bucket, Key=source_key)
            return True
        except Exception as exception:
            self.logger.error('Fail to copy object %s/%s to %s/%s: %s',
                              source_bucket, source_key, target_bucket, target_key, exception)
            return False


    def retrieve_object(self, bucket: str, key: str, target: str) -> str | None:
        '''
        Retrieve an object from a bucket to a file target path.
        Returns ETag on success or None on failure.
        '''
        try:
            response = self.client.get_object(Bucket=bucket, Key=key)
            with open(target, 'wb') as file:
                file.write(response['Body'].read())
            return response.get('ETag', '').strip('"')
        except Exception as exception:
            self.logger.error('Fail to retrieve object %s in bucket %s: %s', key, bucket, exception)
            return None


    def download_object(self, bucket: str, key: str, target: str) -> bool:
        '''Download a large object from a bucket to a file target path'''
        try:
            with open(target, 'wb') as file: # write as binary and treat as stream
                self.client.download_fileobj(Bucket=bucket, Key=key, Fileobj=file)
            return True
        except Exception as exception:
            self.logger.error('Fail to retrieve object %s in bucket %s: %s', key, bucket, exception)
            return False


    def delete_object(self, bucket: str, key: str) -> bool:
        '''Delete an object from a bucket'''
        try:
            self.client.delete_object(Bucket=bucket, Key=key)
            return True
        except Exception as exception:
            self.logger.error('Fail to delete object %s in bucket %s: %s', key, bucket, exception)
            return False