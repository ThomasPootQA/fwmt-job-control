# frozen_string_literal: true

require 'rest-client'
require 'nokogiri'
require 'time'
require 'json'

# Class encapsulating a job SOAP request.
class JobRequest
  CREATE_MESSAGE_TEMPLATE = File.join(__dir__, '../views/create_job_request.xml.erb')
  DUE_DATE = (Time.now.to_date >> 1).to_time.iso8601 # One month from now
  ENDPOINT = 'services/tm/v20/messaging/MessageQueueWs.asmx'
  LAST_ADDRESS = 100
  SOAP_ACTION  = 'http://schemas.consiliumtechnologies.com/wsdl/mobile/2007/07/messaging/SendCreateJobRequestMessage'

  def initialize(params, logger)
    @server     = params['server']
    @user_name  = params['user_name']
    @password   = params['password']
    @survey     = params['survey']
    @world      = params['world']
    @user_names = params['user_names']
    @job_count  = params['job_count'].to_i
    @location   = params['location']
    @logger     = logger
    load_address_files
  end

  def send_create_message
    message_ids = []
    user_names = @user_names.split(',')
    user_names.each do |user_name|
      1.upto(@job_count) do
        job_id = SecureRandom.hex(4)

        case @survey
        when 'CCS'
        when 'GFF'
          response = send_gff_create_message(job_id, user_name)
          message_id = get_message_id(response)
          @logger.info "Totalmobile returned message ID #{message_id} for job #{job_id}"
          message_ids << message_id 
        when 'HH'
        when 'LFS'
        end
      end
    end
    message_ids
  end

  private

  def get_message_id(message)
    xml = Nokogiri::XML(message)
    # We don't care about the XML namespaces in the response XML - we just want to get the message ID.
    xml.remove_namespaces!
    xml.css('Id').text
  end

  def load_address_files
    @north_addresses = JSON.parse(File.read(File.join(__dir__, '../data/addresses_north.json')))
    @east_addresses = JSON.parse(File.read(File.join(__dir__, '../data/addresses_east.json')))
    @south_addresses = JSON.parse(File.read(File.join(__dir__, '../data/addresses_south.json')))
    @west_addresses = JSON.parse(File.read(File.join(__dir__, '../data/addresses_west.json')))
  end

  def select_random_address
    # Select a random address from the addresses instance variable for the chosen location.
    instance_variable_get("@#{@location}_addresses")['addresses'][rand(1..LAST_ADDRESS)]
  end

  def send_gff_create_message(job_id, user_name)
    random_address = select_random_address
    variables = { job_id: job_id,
                  address: random_address,
                  postcode: random_address['postcode'],
                  tla: 'SLC',
                  due_date: DUE_DATE,
                  work_type: 'SS',
                  user_name: user_name,
                  world: @world,
                  additional_properties: nil }

    send_create_job_request_message(variables)
  end

  def send_hh_create_message(job_id, user_name)
    puts 'got here'
    random_address = select_random_address
    variables = { job_id: job_id,
                  address: random_address,
                  postcode: random_address['postcode'],
                  tla: 'Census',
                  due_date: DUE_DATE,
                  work_type: 'HH',
                  user_name: user_name,
                  world: @world,
                  additional_properties: nil }

    send_create_job_request_message(variables)
  end

  def send_create_job_request_message(variables)
    message = ERB.new(File.read(CREATE_MESSAGE_TEMPLATE), 0, '>').result(OpenStruct.new(variables).instance_eval { binding })
    RestClient::Request.execute(method: :post,
                                url: "#{@server}/#{ENDPOINT}",
                                user: @user_name,
                                password: @password,
                                headers: { 'SOAPAction': SOAP_ACTION, 'Content-Type': 'text/xml' },
                                payload: message)
  end
end
