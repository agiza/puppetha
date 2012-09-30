class ClientController < ApplicationController


####
# where to put temporary certs/keys. Trailing slash should be present !
@@tmp_openssl_storage = '/home/puppetizer/puppetizer/tmp/ssl/'

# this is temporary for prototype to work
@@puppetmaster_cert_path = @@tmp_openssl_storage + 'puppetmaster1.XXX.com.crt'

# this is temporary for prototype to work
@@puppetmaster_private_key_path = @@tmp_openssl_storage + 'puppetmaster1.XXX.com.pem'

# set this for debug
@@DEBUG=false

###

  def index
    respond_to do |format|
      format.html # index.html.erb
      format.json { render :nothing => true}
    end
  end

  def new
    real_ip = request.env['HTTP_X_REAL_IP']

    if real_ip.nil?
      raise 'Remote IP is nil. Exiting '
    end


    ec2 = AWS::EC2.new
    @instance = check_client_allowed(ec2,real_ip)
    
    # return 403 and exit if client is not allowed
    if @instance.nil?
      return render :nothing => true, :status => 403
    end 

    # XXX bring us back to our native region ec2.us-east-1.amazonaws.com
    AWS.config(:ec2_endpoint => 'ec2.us-east-1.amazonaws.com')

    ############################################                                     
    # Generate certificates for the new client #
    ############################################
    
    # get hostname of the client private or public depending on its region

    if is_private_ip(ec2, real_ip)
      instance = ec2.instances.filter('private-ip-address', real_ip)
      @dns_name = instance.map {|inst| inst.private_dns_name}.to_s
    elsif is_public_ip(ec2, real_ip)
      instance = ec2.instances.filter('public-ip-address', real_ip)
      @dns_name = instance.map {|inst| inst.public_dns_name}.to_s
    else 
      # we should not reach here
        return render :nothing => true, :status => 403
    end

    # generate keypair and save it in file for giving it back to the requesting client
    key = generate_keypair(@dns_name)
    if key.nil?
      raise 'Could not generate keypair: ' +  @@tmp_openssl_storage +  @dns_name + '.pem'
    end
    
    @client_key = key.to_pem
      
    # generate CSR and save it in file
    csr = generate_csr(@dns_name, key)
    if csr.nil?
      raise 'Could not generate CSR for key: ' + @@tmp_openssl_storage + @dns_name
    end 

    # and sign it with one of our puppetmaster keys/certs

    # this can be a key/cert for any puppetmaster
    # XXX puppetmaster keys should be taken from some shared persitent storage
    # for now we use fs for prototype to work
    ca_cert = get_puppetmaster_cert()
    ca_key = get_puppetmaster_private_key()
     

    # sign it and ssave to a file
    csr_cert  = sign_client(csr,ca_cert, ca_key)
    
    @client_crt = csr_cert.to_pem


    respond_to do |format|
      format.html  {render :layout => false}
    end
  end

  #
  # Checks through all regions if any instance has the remote_ip
  # RETURN VALUES
  # if there is an instance with such remote_ip - returns the instance
  # otherwise                                   - returns nil

  def check_client_allowed(ec2,remote_ip)
    # get all endpoints 
    endpoints = ec2.regions.map(&:endpoint)

    endpoints.each do |endp|
      AWS.config(:ec2_endpoint => endp)

      # check if current instance in the current region has this private ip ?
      instance = is_private_ip(ec2, remote_ip)
      if not instance.nil?
          return instance
      else
        # check if current instance in the current region has this public ip ?
        instance = is_public_ip(ec2, remote_ip)
        if not instance.nil?
          return instance
        end
      end

    end # end of endpoints.each

    # client request is unauthorized
    return nil

  end # end of function check_client_allowed()


  #
  # Checks whether the ip is a public ip address 
  # RETURN VALUES
  # if the ip is a public_ip - returns the instance
  # otherwise                - return nil

  def is_public_ip(ec2,ip)
    return ec2.instances.filter('public-ip-address', ip) 
  end
    
  #
  # Checks whether the ip is a private ip address 
  # RETURN VALUES
  # if the ip is a private_ip - returns the instance
  # otherwise                 - return nil

  def is_private_ip(ec2,ip)
    return ec2.instances.filter('private-ip-address', ip) 
  end
  

  #
  # Generates keypair and writes it to the tmp_openssl_storage/dns_name file
  #
  # RETURN VALUES
  # on exception - nil is returned 
  # on success   - private key is returned (derive pub key from it using public_key method)

  def generate_keypair(dns_name)
    key = OpenSSL::PKey::RSA.new 2048
    if @@DEBUG
      begin
        open @@tmp_openssl_storage + dns_name + '.pem', 'w' do |io| 
          io.write key.to_pem 
        end
        open @@tmp_openssl_storage + dns_name + 'pub.pem', 'w' do |io|
          io.write key.public_key.to_pem
        end
      rescue
        return nil
      end
    end
    return key
  end

  #
  # Certificate signing request is done with CN=dns_name
  # RETURN VALUES
  # csr object is returned  
  def generate_csr(dns_name, key)
    name = OpenSSL::X509::Name.parse 'CN=' + dns_name 
    csr = OpenSSL::X509::Request.new
    csr.version = 2
    csr.subject = name
    csr.public_key = key.public_key
    csr.sign key, OpenSSL::Digest::SHA1.new

      if @@DEBUG
        begin
          open @@tmp_openssl_storage + dns_name + '.csr', 'w' do |io|
            io.write csr.to_pem
          end
        rescue
          raise "Could not write CSR to file: " + @@tmp_openssl_storage + dns_name + '.csr'
        end
      end
    return csr
  end


  #
  # Get puppetmaster certificate
  # XXX this should use dynamodb
  # certificate object or nil is returned
  def get_puppetmaster_cert()
    return  OpenSSL::X509::Certificate.new File.read @@puppetmaster_cert_path
  end 

  #
  # Get puppetmaster private key
  # XXX this should use dynamodb
  # key object or nil is returned
  def get_puppetmaster_private_key()
    return OpenSSL::PKey::RSA.new File.read @@puppetmaster_private_key_path
  end 
  
  #
  # Sign csr with ca_cert and ca_key
  # signed certificate object returned or nil
  def sign_client(csr, ca_cert,ca_key)
    csr_cert = OpenSSL::X509::Certificate.new
    csr_cert.serial = 258
    csr_cert.version = 2
    csr_cert.not_before = Time.now
    csr_cert.not_after = Time.now + 600000 # XXX this should be decided

    csr_cert.subject = csr.subject
    csr_cert.public_key = csr.public_key
    csr_cert.issuer = ca_cert.subject

    extension_factory = OpenSSL::X509::ExtensionFactory.new
    extension_factory.subject_certificate = csr_cert
    extension_factory.issuer_certificate = ca_cert
   

    csr_cert.add_extension extension_factory.create_extension 'authorityKeyIdentifier', 'keyid,issuer:always'
    csr_cert.add_extension extension_factory.create_extension 'basicConstraints', 'critical,CA:FALSE'
    csr_cert.add_extension extension_factory.create_extension 'keyUsage', 'keyEncipherment,digitalSignature'
    csr_cert.add_extension extension_factory.create_extension 'extendedKeyUsage', 'serverAuth, clientAuth'
    csr_cert.add_extension extension_factory.create_extension 'subjectAltName','DNS:puppet','DNS:puppetmaster1.XXX.com'


    csr_cert.sign ca_key, OpenSSL::Digest::SHA1.new

    if @@DEBUG
      begin
        open @@tmp_openssl_storage + csr.subject.to_s + '.crt', 'w' do |io|
          io.write csr_cert.to_pem
        end
      rescue
          raise "Could not write CSR_CRT to file: " + @@tmp_openssl_storage + csr.subject.to_s + '.crt'
      end
    end
    return csr_cert
  end
end

