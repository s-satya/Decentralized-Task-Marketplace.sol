// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title Decentralized Task Marketplace
 * @dev A smart contract for posting tasks, accepting them, and managing payments through escrow
 */
contract Project {
    
    // State variables
    address public owner;
    uint256 public taskCounter;
    uint256 public platformFeePercentage = 5; // 5% platform fee
    
    // Enums
    enum TaskStatus { Open, Assigned, Completed, Disputed, Cancelled }
    
    // Structs
    struct Task {
        uint256 id;
        string title;
        string description;
        uint256 reward;
        address payable client;
        address payable freelancer;
        TaskStatus status;
        uint256 deadline;
        bool clientApproved;
        bool freelancerSubmitted;
    }
    
    // Mappings
    mapping(uint256 => Task) public tasks;
    mapping(address => uint256[]) public userTasks;
    mapping(address => uint256) public userRatings;
    mapping(address => uint256) public completedTasksCount;
    
    // Events
    event TaskCreated(uint256 indexed taskId, address indexed client, string title, uint256 reward);
    event TaskAssigned(uint256 indexed taskId, address indexed freelancer);
    event TaskCompleted(uint256 indexed taskId, address indexed freelancer, address indexed client);
    event TaskCancelled(uint256 indexed taskId, address indexed client);
    event PaymentReleased(uint256 indexed taskId, address indexed freelancer, uint256 amount);
    
    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
    
    modifier onlyClient(uint256 _taskId) {
        require(msg.sender == tasks[_taskId].client, "Only client can call this function");
        _;
    }
    
    modifier onlyFreelancer(uint256 _taskId) {
        require(msg.sender == tasks[_taskId].freelancer, "Only assigned freelancer can call this function");
        _;
    }
    
    modifier taskExists(uint256 _taskId) {
        require(_taskId <= taskCounter && _taskId > 0, "Task does not exist");
        _;
    }
    
    constructor() {
        owner = msg.sender;
        taskCounter = 0;
    }
    
    /**
     * @dev Core Function 1: Create a new task
     * @param _title Task title
     * @param _description Task description
     * @param _deadline Task deadline (timestamp)
     */
    function createTask(
        string memory _title,
        string memory _description,
        uint256 _deadline
    ) external payable {
        require(msg.value > 0, "Task reward must be greater than 0");
        require(_deadline > block.timestamp, "Deadline must be in the future");
        require(bytes(_title).length > 0, "Title cannot be empty");
        
        taskCounter++;
        
        tasks[taskCounter] = Task({
            id: taskCounter,
            title: _title,
            description: _description,
            reward: msg.value,
            client: payable(msg.sender),
            freelancer: payable(address(0)),
            status: TaskStatus.Open,
            deadline: _deadline,
            clientApproved: false,
            freelancerSubmitted: false
        });
        
        userTasks[msg.sender].push(taskCounter);
        
        emit TaskCreated(taskCounter, msg.sender, _title, msg.value);
    }
    
    /**
     * @dev Core Function 2: Accept and get assigned to a task
     * @param _taskId ID of the task to accept
     */
    function acceptTask(uint256 _taskId) external taskExists(_taskId) {
        Task storage task = tasks[_taskId];
        
        require(task.status == TaskStatus.Open, "Task is not available");
        require(task.client != msg.sender, "Client cannot accept their own task");
        require(block.timestamp < task.deadline, "Task deadline has passed");
        
        task.freelancer = payable(msg.sender);
        task.status = TaskStatus.Assigned;
        
        userTasks[msg.sender].push(_taskId);
        
        emit TaskAssigned(_taskId, msg.sender);
    }
    
    /**
     * @dev Core Function 3: Complete task and release payment
     * @param _taskId ID of the task to complete
     */
    function completeTask(uint256 _taskId) external taskExists(_taskId) {
        Task storage task = tasks[_taskId];
        
        if (msg.sender == task.freelancer) {
            require(task.status == TaskStatus.Assigned, "Task is not assigned or already completed");
            task.freelancerSubmitted = true;
        } else if (msg.sender == task.client) {
            require(task.freelancerSubmitted, "Freelancer has not submitted the task yet");
            task.clientApproved = true;
        } else {
            revert("Only client or freelancer can call this function");
        }
        
        // If both freelancer submitted and client approved, release payment
        if (task.freelancerSubmitted && task.clientApproved) {
            task.status = TaskStatus.Completed;
            
            uint256 platformFee = (task.reward * platformFeePercentage) / 100;
            uint256 freelancerPayment = task.reward - platformFee;
            
            // Transfer payment to freelancer
            task.freelancer.transfer(freelancerPayment);
            
            // Transfer platform fee to owner
            payable(owner).transfer(platformFee);
            
            // Update completed tasks count
            completedTasksCount[task.freelancer]++;
            completedTasksCount[task.client]++;
            
            emit TaskCompleted(_taskId, task.freelancer, task.client);
            emit PaymentReleased(_taskId, task.freelancer, freelancerPayment);
        }
    }
    
    // Additional utility functions
    
    /**
     * @dev Cancel a task (only by client, only if not assigned)
     * @param _taskId ID of the task to cancel
     */
    function cancelTask(uint256 _taskId) external onlyClient(_taskId) taskExists(_taskId) {
        Task storage task = tasks[_taskId];
        require(task.status == TaskStatus.Open, "Can only cancel open tasks");
        
        task.status = TaskStatus.Cancelled;
        task.client.transfer(task.reward);
        
        emit TaskCancelled(_taskId, msg.sender);
    }
    
    /**
     * @dev Get task details
     * @param _taskId ID of the task
     */
    function getTask(uint256 _taskId) external view taskExists(_taskId) returns (
        uint256 id,
        string memory title,
        string memory description,
        uint256 reward,
        address client,
        address freelancer,
        TaskStatus status,
        uint256 deadline
    ) {
        Task memory task = tasks[_taskId];
        return (
            task.id,
            task.title,
            task.description,
            task.reward,
            task.client,
            task.freelancer,
            task.status,
            task.deadline
        );
    }
    
    /**
     * @dev Get user's task IDs
     * @param _user Address of the user
     */
    function getUserTasks(address _user) external view returns (uint256[] memory) {
        return userTasks[_user];
    }
    
    /**
     * @dev Get total number of tasks
     */
    function getTotalTasks() external view returns (uint256) {
        return taskCounter;
    }
    
    /**
     * @dev Update platform fee (only owner)
     * @param _newFeePercentage New fee percentage
     */
    function updatePlatformFee(uint256 _newFeePercentage) external onlyOwner {
        require(_newFeePercentage <= 10, "Fee cannot exceed 10%");
        platformFeePercentage = _newFeePercentage;
    }
    
    /**
     * @dev Emergency withdraw (only owner)
     */
    function emergencyWithdraw() external onlyOwner {
        payable(owner).transfer(address(this).balance);
    }
    
    // Fallback function
    receive() external payable {}
}
