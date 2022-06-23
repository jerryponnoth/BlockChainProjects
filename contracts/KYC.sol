pragma solidity ^0.8.0;
contract kyc{
    struct Customer {
        string username;
        string customerData;
        address bank;
        bool kycStatus;
        uint downVotes;
        uint upVotes;
        }

    struct Bank{
        string name;
        address ethAddress;
        string regNumber;
        uint complaintsReported;
        uint kycCount;
        bool isAllowedToVote;
    }

    struct kycRequest{
        string name;
        address ethAddress;
        string customerData;
    }

    //Customer List
    mapping(string => Customer) internal customers;
    //Bank List
    mapping(address =>Bank) internal banks;
    //KYC Request List
    mapping(string => kycRequest) internal requests;
    //Votes by Bank
    mapping(address =>mapping(string => bool)) internal bankVote;
    //Bank Complaint Reporting
    mapping(address =>mapping(address => bool)) internal bankCompaints;
    //Count of Failed KYC verification per Bank
    mapping(address => uint) internal failedReq;

    address private admin;
    uint private bankCount;
    uint constant MIN_VOTE = 3;
    uint constant MIN_BANK_COUNT = 8;
    uint constant MAX_FAILURE = 3;

    constructor()
    {
        admin = msg.sender;
    }

    // Bank Interface Functions

    //This internal functions add customer kyc information
    function addCustomer(string memory _username,string memory _customerData) internal {
        require(customers[_username].bank == address(0),"Duplicate Customer Entry");
        Customer memory customer;
        customer.username = _username;
        customer.customerData = _customerData;
        customer.bank = msg.sender;
        customer.kycStatus = true;
        customers[_username] = customer;
                
    }

    //This external function retrieves customer data from the contract when invoked by a registerd bank
    function getCustomer(string memory _username) external isBankRegistered isCustomerFound(_username)
     view returns(string memory, string memory, bool, address) {
        return (customers[_username].username,customers[_username].customerData,customers[_username].kycStatus,customers[_username].bank);
    }

    //This external function can replace the customer data from the contract when invoked by a registerd bank
    //This is doing a new KYC and replacing the exisitng KYC data
    function setCustomer(string memory _username, string memory _customerData) 
    external isBankRegistered isCustomerFound(_username) returns(string memory){
        if(customers[_username].kycStatus == false)
        {
            //Replace customer 
            delete customers[_username];
            addCustomer(_username,_customerData);
            //Replace request data
            requests[_username].customerData = _customerData;
            requests[_username].ethAddress = msg.sender;
            return "Customer Data Replaced";
        }
        else{
            return "Customer Data Cannot be Replaced";
        }
    }

    //Function for up voting a customer KYC
    function upVoteCustomer(string memory _username) external isBankRegistered isCustomerFound(_username){
        require(banks[msg.sender].isAllowedToVote == true,"Bank is not not allowed to vote");
        require(customers[_username].bank != msg.sender,"The bank that approved KYC cannot Upvote");
        require( bankVote[msg.sender][_username] != true,"Same bank cannot vote for same customer");
        
        
        customers[_username].upVotes += 1;
        bankVote[msg.sender][_username] = true;
        
        // Set KYC Status to True if the KYC upvotes have crossed a threshold vote limit and is greater than down vote
        if (customers[_username].upVotes > MIN_VOTE 
        && customers[_username].upVotes > customers[_username].downVotes)
        {
            customers[_username].kycStatus = true;
        }

        
    }

    //Function for down voting a customer KYC
    function downVoteCustomer(string memory _username) public isBankRegistered isCustomerFound(_username){
        require(banks[msg.sender].isAllowedToVote == true,"Bank is not not allowed to vote");
        require(customers[_username].bank != msg.sender,"The bank that approved KYC cannot DownVote");
        require( bankVote[msg.sender][_username] != true,"Same bank cannot vote for same customer");
        bool isCustomerKYCDownVoted;


        customers[_username].downVotes += 1;
        bankVote[msg.sender][_username] = true;

        // Set KYC Status to False if the KYC downvotes have crossed a threshold vote limit and is greater than up vote
        if (customers[_username].downVotes > MIN_VOTE && 
        customers[_username].downVotes > customers[_username].upVotes)
            {
            customers[_username].kycStatus= false;
            isCustomerKYCDownVoted = true;
            }
        
        // Set KYC Status to False if more than 50 percent of bank down voted 
        if ((bankCount > MIN_BANK_COUNT) && (customers[_username].downVotes > bankCount*50/100 ))
            {
                customers[_username].kycStatus = false;
                isCustomerKYCDownVoted = true;

            }

        //Automatically Report the bank that approved the KYC
        if (isCustomerKYCDownVoted) {
            failedReq[customers[_username].bank] += 1;
        }

    }

    function reportBank(address _bankAdress) public isBankRegistered isBankFound(_bankAdress)  {
        require(bankCompaints[msg.sender][_bankAdress]  != true,"One Bank can report same bank only once");
        banks[_bankAdress].complaintsReported +=1;
        bankCompaints[msg.sender][_bankAdress] = true;
        // If bank received above a threshold complaints from peer banks and
        //  from atleast 30 percent of banks in Network then disable their voting feature
        if (banks[_bankAdress].complaintsReported > MIN_VOTE && banks[_bankAdress].complaintsReported > bankCount*30/100)
        {
            banks[_bankAdress].isAllowedToVote = false;
        }
        
        //if the bank exceed a failure threshold for the number of KYC then disable their voting feature
        if (failedReq[_bankAdress] > MAX_FAILURE) {
            banks[_bankAdress].isAllowedToVote = false;
        }
    }

    //Function used by the bank to initiate a KYC
    function KYCRequest(string memory _username, string memory _customerData) public isBankRegistered returns(bool, string memory) {
        banks[msg.sender].kycCount += 1;

        if(requests[_username].ethAddress != address(0))
        {
            return (false,requests[_username].customerData);
        }
        kycRequest memory kycReq;
        kycReq.name = _username;
        kycReq.ethAddress = msg.sender;
        kycReq.customerData = _customerData;
        requests[_username] = kycReq;
        return (true,"Request entered");
    }

    //Function used by the bank to verify a KYC. This creates a customer data on the contract
    function verifyKYC(string memory _username) public isBankRegistered  {
        require(requests[_username].ethAddress == msg.sender,"The KYC was not requested by the bank");
        addCustomer(_username,requests[_username].customerData);
        
    }

    //used to reject and remove a KYC request. 
    function rejectKYC(string memory _username) isBankRegistered public {
        require(requests[_username].ethAddress == msg.sender,"The KYC was not requested by the bank");
        require(customers[_username].bank == msg.sender,"The KYC is already verified, unable to remove");
        delete requests[_username];
    }

    function getMinDownVote()  external view returns(uint) {
        return bankCount*50/100;
    }

    // Admin Interface

    //Used to add a bank by admin
    function addBank (string memory _name, address _bankAdress,string memory _regNum) public isAdmin
    {
        Bank memory bank;
        bank.ethAddress = _bankAdress;
        bank.name = _name;
        bank.regNumber = _regNum;
        bank.isAllowedToVote = true;
        banks[_bankAdress] = bank;
        bankCount += 1;
    }

    //Used to remove a bank by admin
    function removeBank(address _bankAdress) public isAdmin  isBankFound(_bankAdress) {
        delete banks[_bankAdress];
        bankCount += 1;
    }
    
    //Used to modify the voting feature of a bank by admin
    function isAllowVoting(address _bankAdress, bool vote) public isAdmin  isBankFound(_bankAdress){
        banks[_bankAdress].isAllowedToVote = vote;
    }

    //Used to get the bank name by admin
    function getBank(address _bankAdress) public isAdmin  isBankFound(_bankAdress) view returns(string memory) {
        return banks[_bankAdress].name;
    }

    function getBankCount() public view returns(uint) {
        return bankCount;
    }

    function getBankComplaints(address _bankAdress) public isAdmin isBankFound(_bankAdress) view returns(uint) {
        return banks[_bankAdress].complaintsReported;
    }

    function getMinBankComplaints(address _bankAdress) public isAdmin isBankFound(_bankAdress) view returns(uint) {
        if (banks[_bankAdress].complaintsReported > MIN_VOTE)
        {
            return bankCount*30/100;
        }
        else
        {
            return MIN_VOTE;
        }
               
    }

    //Modifiers 
    modifier isAdmin(){
        require(msg.sender == admin,"Only Admin can use this function");
        _;
    }

    modifier isBankRegistered(){
        require(banks[msg.sender].ethAddress != address(0),"Only Registered Bank can use this function");
        _;
    }


    modifier isBankFound(address _bankAdress){
        require(banks[_bankAdress].ethAddress != address(0),"Bank Address not found");    
        _;
    }

    modifier isCustomerFound(string memory _username){
        require(customers[_username].bank != address(0),"Customer not found");  
        _;
    }

}